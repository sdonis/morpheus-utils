
# CONFIG
NAMESPACE='<%= customOptions.namespace %>'
RELEASE_NAME="librechat"
DOMAIN="librechat.ejemplo.com"
INGRESS_CLASS="nginx"
ALLOW_REGISTRATION="true"
OPENAI_API_KEY="dummy"
VLLM_BASE_URL="http://vllmruntime-sample.vllm.svc.cluster.local:80/v1"
VLLM_MODEL='<%= customOptions.vllmModel %>'

# CREDENTIALS
CREDS_KEY=$(openssl rand -hex 32)
CREDS_IV=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)
MEILI_MASTER_KEY=$(openssl rand -hex 32)

set -euo pipefail

echo "������ Verificando conectividad con vLLM..."
if kubectl run vllm-test --image=busybox --restart=Never --rm -i \
  --namespace default \
  -- wget -qO- --timeout=5 "${VLLM_BASE_URL}/models" 2>/dev/null; then
  echo "✅ vLLM accessible"
else
  echo "⚠️  Advertencia: no se pudo alcanzar vLLM en ${VLLM_BASE_URL}"
  echo "   Verify with: kubectl get svc -n vllm"
fi

# 1. Namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 2. Secret with credentials
# Chart reads CREDS_KEY, CREDS_IV, JWT_SECRET, JWT_REFRESH_SECRET, MEILI_MASTER_KEY
# from existingSecretName - all should be here.
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: librechat-credentials-env
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  CREDS_KEY: "${CREDS_KEY}"
  CREDS_IV: "${CREDS_IV}"
  JWT_SECRET: "${JWT_SECRET}"
  JWT_REFRESH_SECRET: "${JWT_REFRESH_SECRET}"
  MEILI_MASTER_KEY: "${MEILI_MASTER_KEY}"
  OPENAI_API_KEY: "${OPENAI_API_KEY}"
EOF

cat > /tmp/librechat-values.yaml <<EOF
librechat:
  existingSecretName: "librechat-credentials-env"

  configEnv:
    ALLOW_REGISTRATION: "${ALLOW_REGISTRATION}"
    ALLOW_EMAIL_LOGIN: "true"
    DOMAIN_SERVER: "https://${DOMAIN}"
    DOMAIN_CLIENT: "https://${DOMAIN}"

  configYamlContent: |
    version: 1.2.8
    cache: true
    endpoints:
      custom:
        - name: "Llama 3.1 8B"
          apiKey: "empty"
          baseURL: "${VLLM_BASE_URL}"
          models:
            default: ["${VLLM_MODEL}"]
            fetch: true
          titleConvo: true
          titleModel: "current_model"
          titleMessageRole: "user"
          summarize: false
          summaryModel: "current_model"
          forcePrompt: false

ingress:
  enabled: true
  className: "${INGRESS_CLASS}"
  hosts:
    - host: ${DOMAIN}
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: librechat-tls
      hosts:
        - ${DOMAIN}

mongodb:
  image:
    repository: mongo
    tag: "7"
  podSecurityContext:
    fsGroup: 999
  containerSecurityContext:
    runAsUser: 999
    runAsNonRoot: true
EOF

# 4. Install with Helm
helm upgrade --install "$RELEASE_NAME" \
  oci://ghcr.io/danny-avila/librechat-chart/librechat \
  --version 2.0.1 \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout 10m \
  --values /tmp/librechat-values.yaml

echo ""
echo "✅ LibreChat installed in https://${DOMAIN}"
echo ""

# VERIFY INSTALLATION
DEPLOY="${RELEASE_NAME}-librechat"

echo "������ Verifying config inside the pod..."
kubectl exec -n "$NAMESPACE" deploy/"$DEPLOY" -- \
  sh -c 'cat /app/librechat.yaml 2>/dev/null || find /app -name "*.yaml" 2>/dev/null | head -10' \
  && echo "✅ Config found" \
  || echo "❌ Config not found"

echo ""
echo "������ State of the pods:"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "������ Relevant Logs:"
kubectl logs -n "$NAMESPACE" deploy/"$DEPLOY" --tail=40 \
  | grep -iE "llama|vllm|custom|config|error|warn|endpoint" || true
