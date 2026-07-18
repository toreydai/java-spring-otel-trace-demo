# Spring Cloud 微服务 + OpenTelemetry + Amazon EKS 完整部署指南

在 EKS 上部署 4 个 Spring Boot 微服务，通过 OpenTelemetry Java Agent 实现零代码侵入的分布式链路追踪，trace 数据经 AWS ADOT Collector 汇聚后导出到 AWS X-Ray。

## 架构

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

### 核心亮点

- **零代码侵入**：OpenTelemetry Java Agent 通过 `ENTRYPOINT` 的 `-javaagent` 参数激活，无需修改业务代码
- **镜像自包含**：Agent 在构建期打入镜像并做 SHA-256 校验，Pod 启动无网络依赖，本地 `docker run` 同样生效
- **X-Ray 完整链路**：`OTEL_PROPAGATORS=xray,tracecontext,baggage` 兼容 ALB 注入的 `X-Amzn-Trace-Id`，Service Map 入口链路完整可见
- **安全最佳实践**：IRSA 最小权限 + CPU limits 防资源抢占 + `imagePullPolicy: Always` 确保版本一致

拓扑、架构图与 OTel 埋点原理见 [`docs/architecture.md`](docs/architecture.md)。

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

## 前置要求

- AWS 账号 + EKS 集群（本文使用: `test`，区域: `ap-southeast-1`）
- kubectl 已配置
- Docker + Maven 3.8+

```bash
for SERVICE in gateway-service user-service order-service product-service; do
  aws ecr create-repository --repository-name $SERVICE --region ap-southeast-1
done
```

## 快速开始

```bash
# 1. 改 Cmds/build-and-push.sh 里的 AWS_REGION / AWS_ACCOUNT_ID，构建并推送镜像
./Cmds/build-and-push.sh

# 2. 配置 IRSA（otel-collector 需要 X-Ray 写入权限），部署到 EKS
kubectl apply -f Infra/otel-collector.yaml
kubectl apply -f Infra/applications.yaml

# 3. 起流量生成器，持续产生调用链
kubectl apply -f Infra/traffic-generator.yaml
```

CloudWatch → X-Ray traces → Service map 即可看到 4 个服务节点及调用关系。完整分步说明（IAM policy、每步预期输出、故障排查）见 [`docs/deployment.md`](docs/deployment.md)。

## 清理

```bash
./Cmds/cleanup.sh
```

清理范围：Kubernetes 资源、ECR 仓库、IAM Service Account、IAM 策略。执行前需输入 `yes` 确认。

## License

MIT - see the [LICENSE](LICENSE) file for details.

## 免责声明

- 本项目仅供学习与技术参考，不构成生产部署方案。
- 运行过程中会创建 AWS 资源并产生费用，请在实验结束后及时清理。
- 作者不对因使用本项目产生的任何费用或损失承担责任。
- 本项目与 Amazon Web Services 无官方关联，相关服务的可用性与定价以 AWS 官方文档为准。
- 生产环境使用前请根据实际需求进行安全评估与调整。
