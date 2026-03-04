NAMESPACE='<%= customOptions.namespace %>'
IMAGE_TAG='<%= customOptions.imageTag %>'
MLFLOW_IMAGE="ghcr.io/mlflow/mlflow:${IMAGE_TAG}"

echo "Creating namespace $NAMESPACE..."
kubectl create namespace $NAMESPACE || true

echo "Checking if MLflow deployments are already present..."
REQUIRED_DEPLOYMENTS=("mlflow" "postgres" "minio")
deploy_exist=true

for dep in "${REQUIRED_DEPLOYMENTS[@]}"; do
    if ! kubectl get deployment $dep -n "$NAMESPACE" >/dev/null 2>&1; then
        deploy_exist=false
        break
    fi
done

echo "Checking if MLflow services are already present..."
REQUIRED_SERVICES=("mlflow" "postgres" "minio")
svc_exist=true

for svc in "${REQUIRED_SERVICES[@]}"; do
    if ! kubectl get svc $svc -n "$NAMESPACE" >/dev/null 2>&1; then
        svc_exist=false
        break
    fi
done

if [ "$deploy_exist" = true ] && [ "$svc_exist" = true ]; then
    echo "All Deployments & Services already exist in $NAMESPACE. Skipping installation."
    exit 0
else
    echo "Some resources missing in $NAMESPACE. Continuing with the installation..."
fi

# 1) Desplegar PostgreSQL

echo "Deploying PostgreSQL..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Secret
metadata:
  name: pg-secret
type: Opaque
stringData:
  POSTGRES_USER: mlflow
  POSTGRES_PASSWORD: mlflow123
  POSTGRES_DB: mlflowdb
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
          - name: POSTGRES_DB
            valueFrom:
              secretKeyRef:
                name: pg-secret
                key: POSTGRES_DB
          - name: POSTGRES_USER
            valueFrom:
              secretKeyRef:
                name: pg-secret
                key: POSTGRES_USER
          - name: POSTGRES_PASSWORD
            valueFrom:
              secretKeyRef:
                name: pg-secret
                key: POSTGRES_PASSWORD
        ports:
        - containerPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  type: ClusterIP
  ports:
  - port: 5432
    targetPort: 5432
  selector:
    app: postgres
EOF

# 2) Desplegar MinIO (Artifact Store)

echo "Deploying MinIO..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Secret
metadata:
  name: minio-creds
type: Opaque
stringData:
  accesskey: minioadmin
  secretkey: minioadmin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args:
        - server
        - /data
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-creds
              key: accesskey
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-creds
              key: secretkey
        ports:
        - containerPort: 9000
---
apiVersion: v1
kind: Service
metadata:
  name: minio
spec:
  type: ClusterIP
  ports:
  - port: 9000
    targetPort: 9000
  selector:
    app: minio
EOF

# 3) Desplegar MLflow Server

echo "Deploying MLflow..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow
  template:
    metadata:
      labels:
        app: mlflow
    spec:
      containers:
      - name: mlflow
        image: $MLFLOW_IMAGE
        ports:
        - containerPort: 5000
        env:
          - name: MLFLOW_TRACKING_URI
            value: "http://0.0.0.0:5000"
          - name: MLFLOW_S3_ENDPOINT_URL
            value: "http://minio:9000"
          - name: AWS_ACCESS_KEY_ID
            valueFrom:
              secretKeyRef:
                name: minio-creds
                key: accesskey
          - name: AWS_SECRET_ACCESS_KEY
            valueFrom:
              secretKeyRef:
                name: minio-creds
                key: secretkey
          - name: MLFLOW_BACKEND_STORE_URI
            value: "postgresql://mlflow:mlflow123@postgres:5432/mlflowdb"
        command: ["mlflow", "server", "--host", "0.0.0.0", "--port", "5000", \
                 "--backend-store-uri", "\$(MLFLOW_BACKEND_STORE_URI)", \
                 "--default-artifact-root", "s3://mlflow-artifacts"]
---
apiVersion: v1
kind: Service
metadata:
  name: mlflow
spec:
  type: NodePort
  ports:
  - port: 5000
    targetPort: 5000
    nodePort: 31279
  selector:
    app: mlflow
EOF

echo "MLflow correctly installed in Kubernetes!"
echo "open mlflow at http://node-ip:31279"
