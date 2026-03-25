git clone https://github.com/kubeflow/manifests.git
cd manifests
git checkout master

kubectl apply -k common/cert-manager/base
kubectl apply -k common/cert-manager/kubeflow-issuer/base

echo "Waiting for cert-manager to be ready ..."
kubectl wait --for=condition=Ready pod -l 'app in (cert-manager,webhook)' --timeout=180s -n cert-manager
kubectl wait --for=jsonpath='{.subsets[0].addresses[0].targetRef.kind}'=Pod endpoints -l 'app in (cert-manager,webhook)' --timeout=180s -n cert-manager

sleep 10 

echo "Installing Istio CNI configured with external authorization..."
kubectl apply -k common/istio/istio-crds/base
kubectl apply -k common/istio/istio-namespace/base

# For most platforms
kubectl apply -k common/istio/istio-install/overlays/oauth2-proxy

echo "Waiting for all Istio Pods to become ready..."
kubectl wait --for=condition=Ready pods --all -n istio-system --timeout=300s

sleep 10

echo "Installing oauth2-proxy..."
kubectl apply -k common/oauth2-proxy/overlays/m2m-dex-only/
kubectl wait --for=condition=Ready pod -l 'app.kubernetes.io/name=oauth2-proxy' --timeout=180s -n oauth2-proxy
sleep 10

echo "Installing Dex..."
kubectl apply -k common/dex/overlays/oauth2-proxy
kubectl wait --for=condition=Ready pods --all --timeout=180s -n auth
sleep 10

echo "Installing Knative Serving..."
kubectl apply -k common/knative/knative-serving/overlays/gateways
kubectl apply -k common/istio/cluster-local-gateway/base
sleep 10

echo "Installing Kubeflow Namespace..."
kubectl apply -k common/kubeflow-namespace/base

echo "Installing Network Policies..."
kubectl apply -k common/networkpolicies/base
sleep 10 

echo "Installing Kubeflow Roles..."
kubectl apply -k common/kubeflow-roles/base

echo "Installing Istio Kubeflow Resources..."
kubectl apply -k common/istio/kubeflow-istio-resources/base
sleep 10

echo "Installing Cert-Manager for multi-user..."
kubectl apply -k applications/pipeline/upstream/env/cert-manager/platform-agnostic-multi-user
sleep 10

echo "Installing KServe..."
kubectl apply --server-side --force-conflicts -k applications/kserve/kserve
kubectl apply -k applications/kserve/models-web-app/overlays/kubeflow
sleep 10

echo "Installing Katib..."
kubectl apply -k applications/katib/upstream/installs/katib-with-kubeflow
sleep 10

echo "Installing Central Dashboard..."
kubectl apply -k applications/centraldashboard/overlays/oauth2-proxy
sleep 10

echo "Installing Admission Webhook with Cert-Manager..."
kubectl apply -k applications/admission-webhook/upstream/overlays/cert-manager
sleep 10

echo "Installing Jupyter Notebook Controller and Jupyter Web App..."
kubectl apply -k applications/jupyter/notebook-controller/upstream/overlays/kubeflow
sleep 20 

kubectl apply -k applications/jupyter/jupyter-web-app/upstream/overlays/istio
sleep 10 

echo "Installing PVC Viewer..."
kubectl apply -k applications/pvcviewer-controller/upstream/base
sleep 10

echo "Installing Profiles Controller..."
kubectl apply -k applications/profiles/upstream/overlays/kubeflow
sleep 10

kubectl apply -k applications/volumes-web-app/upstream/overlays/istio

echo "Installing TensorBoard..."
kubectl apply -k applications/tensorboard/tensorboards-web-app/upstream/overlays/istio
sleep 10

kubectl apply -k applications/tensorboard/tensorboard-controller/upstream/overlays/kubeflow
sleep 10

echo "Installing Training Operator..."
kubectl apply --server-side --force-conflicts -k applications/training-operator/upstream/overlays/kubeflow
sleep 10

echo "Creating default profile..."
kubectl apply -k common/user-namespace/base
sleep 10

echo "Kubeflow installation is complete!"
echo "kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80"
