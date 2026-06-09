#!/bin/bash

set -e

echo "=========================================="
echo "清理 Spring Cloud Demo 资源"
echo "=========================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
REGION="ap-southeast-1"
CLUSTER_NAME="test"
NAMESPACE="default"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "${YELLOW}当前配置:${NC}"
echo "  区域: $REGION"
echo "  集群: $CLUSTER_NAME"
echo "  命名空间: $NAMESPACE"
echo "  AWS账号: $AWS_ACCOUNT_ID"
echo ""

read -p "确认删除所有资源? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "取消操作"
    exit 0
fi

echo ""
echo -e "${GREEN}步骤 1/4: 删除 Kubernetes 资源${NC}"
echo "----------------------------------------"

if kubectl delete -f Infra/traffic-generator.yaml 2>/dev/null; then
    echo "✓ 删除流量生成器"
else
    echo "⚠ 流量生成器不存在或已删除"
fi

if kubectl delete -f Infra/applications.yaml 2>/dev/null; then
    echo "✓ 删除应用服务"
else
    echo "⚠ 应用服务不存在或已删除"
fi

if kubectl delete -f Infra/otel-collector.yaml 2>/dev/null; then
    echo "✓ 删除 OTEL Collector"
else
    echo "⚠ OTEL Collector不存在或已删除"
fi

echo ""
echo "等待资源清理完成..."
sleep 5

echo ""
echo -e "${GREEN}步骤 2/4: 删除 ECR 仓库${NC}"
echo "----------------------------------------"

SERVICES=("gateway-service" "user-service" "order-service" "product-service")

for SERVICE in "${SERVICES[@]}"; do
    if aws ecr describe-repositories --repository-names $SERVICE --region $REGION >/dev/null 2>&1; then
        aws ecr delete-repository --repository-name $SERVICE --force --region $REGION
        echo "✓ 删除 ECR 仓库: $SERVICE"
    else
        echo "⚠ ECR 仓库不存在: $SERVICE"
    fi
done

echo ""
echo -e "${GREEN}步骤 3/4: 删除 IAM Service Account${NC}"
echo "----------------------------------------"

if eksctl get iamserviceaccount --cluster $CLUSTER_NAME --name adot-collector --namespace $NAMESPACE --region $REGION >/dev/null 2>&1; then
    eksctl delete iamserviceaccount \
        --name adot-collector \
        --namespace $NAMESPACE \
        --cluster $CLUSTER_NAME \
        --region $REGION
    echo "✓ 删除 IAM Service Account"
else
    echo "⚠ IAM Service Account 不存在或已删除"
fi

echo ""
echo -e "${GREEN}步骤 4/4: 删除 IAM 策略${NC}"
echo "----------------------------------------"

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSDistroOpenTelemetryXRayPolicy"

if aws iam get-policy --policy-arn $POLICY_ARN >/dev/null 2>&1; then
    aws iam delete-policy --policy-arn $POLICY_ARN
    echo "✓ 删除 IAM 策略"
else
    echo "⚠ IAM 策略不存在或已删除"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "清理完成!"
echo "==========================================${NC}"
echo ""
echo "验证清理结果:"
kubectl get pods -n $NAMESPACE | grep -E "gateway|user|order|product|traffic|otel" || echo "✓ 所有 Pods 已删除"
kubectl get svc -n $NAMESPACE | grep -E "gateway|user|order|product" || echo "✓ 所有 Services 已删除"
echo ""
echo -e "${YELLOW}注意: 如需删除 EKS 集群本身，请手动执行:${NC}"
echo "  eksctl delete cluster --name $CLUSTER_NAME --region $REGION"
