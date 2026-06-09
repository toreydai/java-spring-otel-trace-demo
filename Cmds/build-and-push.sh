#!/bin/bash
set -e

# 配置
AWS_REGION="ap-southeast-1"
AWS_ACCOUNT_ID="123456789012"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# 服务列表
SERVICES=("gateway-service" "user-service" "order-service" "product-service")

echo "=== 登录到ECR ==="
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# 构建和推送镜像
for SERVICE in "${SERVICES[@]}"; do
    echo "=== 构建 ${SERVICE} ==="
    (
        cd App/${SERVICE}
        mvn clean package -DskipTests
        docker build -t ${SERVICE}:latest .
        docker tag ${SERVICE}:latest ${ECR_REGISTRY}/${SERVICE}:latest
        docker tag ${SERVICE}:latest ${ECR_REGISTRY}/${SERVICE}:v1.0.0
        echo "=== 推送 ${SERVICE} ==="
        docker push ${ECR_REGISTRY}/${SERVICE}:latest
        docker push ${ECR_REGISTRY}/${SERVICE}:v1.0.0
        docker rmi ${SERVICE}:latest ${ECR_REGISTRY}/${SERVICE}:latest ${ECR_REGISTRY}/${SERVICE}:v1.0.0 || true
    )
done

echo "=== 所有镜像构建和推送完成 ==="
