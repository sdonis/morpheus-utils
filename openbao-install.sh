#!/bin/bash

NAMESPACE='<%= customOptions.namespace %>'
POD="openbao-0"
KEYS_PATH="/keys"

echo "Creating namespace $NAMESPACE..."
kubectl create namespace $NAMESPACE || echo "Namespace $NAMESPACE already exists, skipping..."


echo "Creating PVC for keys storage..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openbao-keys
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: wekafs
EOF


echo "🚀 Initializing OpenBao..."

helm repo add openbao https://openbao.github.io/openbao-helm
helm install openbao openbao/openbao \
  -n $NAMESPACE \
  --set server.volumes[0].name=bao-keys \
  --set server.volumes[0].persistentVolumeClaim.claimName=openbao-keys \
  --set server.volumeMounts[0].name=bao-keys \
  --set server.volumeMounts[0].mountPath=/keys


echo "Waiting for openbao-0 pod to be ready..."
while true; do
  STATUS=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.phase}')
  
  if [ "$STATUS" == "Running" ]; then
    echo "✅ Pod is Running!"
    break
  fi

  echo "⏳ Current status: $STATUS"
  sleep 3
done
echo "Pod ready"

INIT_OUTPUT=$(kubectl exec -n $NAMESPACE $POD -- bao operator init)

echo "🔑 Extracting keys..."

# Extract keys
KEYS=($(echo "$INIT_OUTPUT" | grep "Unseal Key" | awk '{print $4}'))

# Extract root token
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | grep "Initial Root Token" | awk '{print $4}')

echo "Writing keys directly into pod (PVC)..."



echo "✅ Keys stored in PVC ($KEYS_PATH)"
kubectl exec -n $NAMESPACE $POD -- mkdir -p /keys
for key in "${KEYS[@]}"; do
  kubectl exec -n $NAMESPACE $POD -- sh -c "echo '$key' >> /keys/unseal-keys.txt"
done
kubectl exec -n $NAMESPACE $POD -- sh -c "echo '$ROOT_TOKEN' > /keys/root-token.txt"
kubectl exec -n $NAMESPACE $POD -- chmod 600 /keys/*

echo "🔓 Unsealing..."

#read keys from PVC
KEYS_FROM_POD=($(kubectl exec -n $NAMESPACE $POD -- cat /keys/unseal-keys.txt))

# Threshold = 3
for i in 0 1 2
do
  kubectl exec -n $NAMESPACE $POD -- bao operator unseal ${KEYS_FROM_POD[$i]}
done

echo "🎉 OpenBao unsealed!"
echo "Export openbao svc to NodePort and port-forward"
echo "Use the token in /keys/root-token.txt to login and start using OpenBao using the following command"
echo "kubectl exec -n $NAMESPACE $POD -- cat /keys/root-token.txt"

# Opcional: login automático
#kubectl exec -n $NAMESPACE $POD -- bao login $ROOT_TOKEN
