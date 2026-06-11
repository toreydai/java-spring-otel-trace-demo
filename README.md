# Spring Cloud 微服务 + OpenTelemetry + Amazon EKS 完整部署指南

## 目录
1. [架构概览](#架构概览)
2. [前置要求](#前置要求)
3. [项目代码说明](#项目代码说明)
4. [步骤1: 构建和推送镜像](#步骤1-构建和推送镜像)
5. [步骤2: 配置EKS权限](#步骤2-配置eks权限)
6. [步骤3: 部署到EKS](#步骤3-部署到eks)
7. [步骤4: 创建持续流量生成器](#步骤4-创建持续流量生成器)
8. [步骤5: 查看链路追踪](#步骤5-查看链路追踪)
9. [故障排查](#故障排查)
10. [清理资源](#清理资源)
11. [总结](#总结)

---

## 架构概览

```
Internet → Gateway Service (LoadBalancer)
              │
              ├─→ User Service
              ├─→ Order Service ──→ User Service
              │                 └─→ Product Service
              └─→ Product Service

所有服务 ──traces──▶ ADOT Collector ──▶ AWS X-Ray
```

### 技术栈
- Java 17 + Spring Boot 2.7.18 + Amazon Corretto 17 Alpine
- OpenTelemetry Java Agent 2.24.0（零代码侵入，打入镜像）
- AWS ADOT Collector v0.42.0
- AWS X-Ray + CloudWatch

### 项目结构

```
├── App/                          # 4 个微服务代码
│   ├── gateway-service/          # API 网关 (LoadBalancer)
│   ├── user-service/             # 用户服务
│   ├── order-service/            # 订单服务（调用 User + Product）
│   └── product-service/          # 产品服务
├── Infra/                        # K8s 配置
│   ├── otel-collector.yaml       # ADOT Collector
│   ├── applications.yaml         # 应用部署
│   └── traffic-generator.yaml    # 流量生成器
└── Cmds/                         # 自动化脚本
    ├── build-and-push.sh         # 构建并推送镜像
    └── cleanup.sh                # 清理资源
```

---

## 前置要求

- AWS 账号 + EKS 集群（本文使用: `test`，区域: `ap-southeast-1`）
- kubectl 已配置
- Docker + Maven 3.8+

### 创建 ECR 仓库

```bash
for SERVICE in gateway-service user-service order-service product-service; do
  aws ecr create-repository --repository-name $SERVICE --region ap-southeast-1
done
```

---

## 项目代码说明

### OTEL Agent 内置于镜像

OTel Java Agent 在 `docker build` 阶段下载并写入镜像，不依赖运行时网络。构建时会校验 SHA-256，防止损坏或篡改的 jar 静默打入镜像。

```dockerfile
RUN mkdir /otel && \
    wget -q -O /otel/opentelemetry-javaagent.jar \
    https://github.com/.../v2.24.0/opentelemetry-javaagent.jar && \
    echo "5c48cd...  /otel/opentelemetry-javaagent.jar" | sha256sum -c
ENTRYPOINT ["java", "-javaagent:/otel/opentelemetry-javaagent.jar", "-jar", "app.jar"]
```

Agent 通过 `ENTRYPOINT` 激活，镜像自包含，`docker run` 本地运行时同样生效。

### K8s 关键配置

**applications.yaml** 每个服务包含：

| 配置项 | 值 | 说明 |
|--------|----|------|
| `imagePullPolicy` | `Always` | 确保每次调度都拉取最新镜像 |
| `OTEL_PROPAGATORS` | `xray,tracecontext,baggage` | 兼容 X-Ray 和 W3C 格式，保证入口链路完整 |
| `resources.limits.cpu` | `500m` | 防止 GC 风暴抢占节点 CPU |
| `resources.requests.cpu` | `100m` | 调度保障 |

---

## 步骤1: 构建和推送镜像

### 1.1 修改构建脚本配置

编辑 `Cmds/build-and-push.sh`，将以下两个变量改为实际值：

```bash
AWS_REGION="ap-southeast-1"      # 改为你的区域
AWS_ACCOUNT_ID="123456789012"    # 改为你的 AWS 账号 ID
```

### 1.2 修改 applications.yaml 镜像地址

```bash
sed -i 's/123456789012/YOUR_ACCOUNT_ID/g' Infra/applications.yaml
```

如果使用其他区域，同时修改 `Infra/otel-collector.yaml` 中的区域：

```yaml
awsxray:
  region: ap-southeast-1  # 改为你的区域
```

### 1.3 执行构建

```bash
chmod +x Cmds/build-and-push.sh
./Cmds/build-and-push.sh
```

脚本自动完成：登录 ECR → Maven 构建 JAR → Docker 构建镜像（含 OTEL agent 下载和校验）→ 推送到 ECR → 清理本地镜像。

> **注意**：构建时需要访问 GitHub 下载 OTEL agent。如果 CI/CD 环境出站受限，请提前将 agent jar 上传到 S3 并修改 Dockerfile 中的下载地址。

---

## 步骤2: 配置EKS权限

使用 **IRSA (IAM Roles for Service Accounts)** 为 ADOT Collector 配置 X-Ray 写入权限：

```bash
# 1. 创建 IAM 策略
cat > xray-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords"
    ],
    "Resource": "*"
  }]
}
EOF

aws iam create-policy \
  --policy-name AWSDistroOpenTelemetryXRayPolicy \
  --policy-document file://xray-policy.json \
  --region ap-southeast-1

# 2. 创建 Service Account 并关联 IAM 角色
eksctl create iamserviceaccount \
  --name adot-collector \
  --namespace default \
  --cluster test \
  --region ap-southeast-1 \
  --attach-policy-arn arn:aws:iam::123456789012:policy/AWSDistroOpenTelemetryXRayPolicy \
  --approve \
  --override-existing-serviceaccounts
```

---

## 步骤3: 部署到EKS

```bash
# 1. 先部署 ADOT Collector
kubectl apply -f Infra/otel-collector.yaml

# 2. 再部署应用服务
kubectl apply -f Infra/applications.yaml

# 3. 等待所有 Pod 就绪
kubectl get pods -w
```

预期所有 Pod 均为 `Running`（约 1-2 分钟）：

```
NAME                               READY   STATUS    RESTARTS   AGE
gateway-service-xxx-xxx            1/1     Running   0          2m
order-service-xxx-xxx              1/1     Running   0          2m
otel-collector-xxx-xxx             1/1     Running   0          2m
product-service-xxx-xxx            1/1     Running   0          2m
user-service-xxx-xxx               1/1     Running   0          2m
```

获取 Gateway 访问地址：

```bash
kubectl get svc gateway-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## 步骤4: 创建持续流量生成器

```bash
kubectl apply -f Infra/traffic-generator.yaml

# 查看日志
kubectl logs -f deployment/continuous-traffic-generator
```

流量生成器每 25 秒循环一轮，模拟以下业务流程：

1. `GET /api/products` — 查看产品列表
2. `GET /api/users` — 查看用户信息
3. `GET /api/orders` — 创建订单（触发完整调用链）
4. `GET /api/orders` — 查询订单状态

2 个副本并发运行，自动持续产生链路追踪数据，无需手动触发。

---

## 步骤5: 查看链路追踪

1. 登录 AWS 控制台 → 选择 `ap-southeast-1` 区域 → 进入 **CloudWatch**
2. 左侧菜单：**X-Ray traces → Service map**，可看到 4 个服务节点及调用关系
3. 左侧菜单：**X-Ray traces → Traces**，过滤业务请求：

```
http.url CONTAINS "/api/"
```

示例 Trace 结构：

```
gateway-service (50ms)
  └─ GET /api/orders
     └─ order-service (40ms)
        ├─ GET http://user-service:8080/users (15ms)
        └─ GET http://product-service:8080/products (20ms)
```

---

## 故障排查

**检查所有资源状态**
```bash
kubectl get pods,svc,endpoints
```

**查看 Pod 日志**
```bash
kubectl logs <pod-name>
kubectl logs <pod-name> --previous   # 查看上次崩溃日志
```

**检查 ADOT Collector**
```bash
kubectl logs -l app=otel-collector | grep -i "error\|AccessDenied"
```

**测试服务连通性**
```bash
kubectl exec -it <gateway-pod> -- wget -qO- http://user-service:8080/actuator/health
```

**常见问题**

| 现象 | 排查方向 |
|------|---------|
| `ImagePullBackOff` | 检查 ECR 权限、账号 ID 是否替换 |
| `CrashLoopBackOff` | `kubectl logs <pod> --previous` 查看启动错误 |
| X-Ray 无数据 | 检查 Collector 日志和 IRSA 权限；确认 `OTEL_PROPAGATORS` 已设置 |
| 服务调用失败 | 检查 Service 和 Endpoints 是否正常 |

---

## 清理资源

```bash
chmod +x Cmds/cleanup.sh
./Cmds/cleanup.sh
```

脚本清理范围：Kubernetes 资源（Pod/Service/Deployment）、ECR 仓库、IAM Service Account、IAM 策略。执行前需输入 `yes` 确认。

---

## 总结

本方案演示了如何在 EKS 上部署 Spring Boot 微服务，并通过 OpenTelemetry 实现**零代码侵入**的分布式链路追踪。

### 核心亮点

**零代码侵入**  
OpenTelemetry Java Agent 通过 `ENTRYPOINT` 的 `-javaagent` 参数激活，无需修改任何业务代码。

**镜像自包含**  
Agent 在构建期打入镜像并做 SHA-256 校验，Pod 启动无网络依赖，本地 `docker run` 同样生效。

**X-Ray 完整链路**  
设置 `OTEL_PROPAGATORS=xray,tracecontext,baggage`，兼容 ALB 注入的 `X-Amzn-Trace-Id`，Service Map 入口链路完整可见。

**安全最佳实践**  
IRSA 最小权限 + CPU limits 防资源抢占 + `imagePullPolicy: Always` 确保版本一致性。

### 调用链路

```
用户请求 → Gateway → Order Service → User Service
                                   → Product Service
```

## 免责声明

本项目仅供学习与技术参考，不构成生产部署方案。运行过程中会创建 AWS 资源并产生费用，请在实验结束后及时清理。作者不对因使用本项目产生的任何费用或损失承担责任。本项目与 Amazon Web Services 无官方关联，相关服务的可用性与定价以 AWS 官方文档为准。生产环境使用前请根据实际需求进行安全评估与调整。
