git clone https://github.com/kubeflow/manifests.git
cd manifests
git checkout master
kustomize build common/cert-manager/base | kubectl apply -f -
kustomize build common/cert-manager/kubeflow-issuer/base | kubectl apply -f -
echo "Waiting for cert-manager to be ready ..."
kubectl wait --for=condition=Ready pod -l 'app in (cert-manager,webhook)' --timeout=180s -n cert-manager
kubectl wait --for=jsonpath='{.subsets[0].addresses[0].targetRef.kind}'=Pod endpoints -l 'app in (cert-manager,webhook)' --timeout=180s -n cert-manager
sleep 10 
echo "Installing Istio CNI configured with external authorization..."
kustomize build common/istio/istio-crds/base | kubectl apply -f -
kustomize build common/istio/istio-namespace/base | kubectl apply -f -
# For most platforms (Kind, Minikube, AKS, EKS, etc.)
kustomize build common/istio/istio-install/overlays/oauth2-proxy | kubectl apply -f -
echo "Waiting for all Istio Pods to become ready..."
kubectl wait --for=condition=Ready pods --all -n istio-system --timeout 300s
sleep 10
echo "Installing oauth2-proxy..."
# Only uncomment ONE of the following overlays, as they are mutually exclusive.
# See `common/oauth2-proxy/overlays/` for more options.
# OPTION 1: works on most clusters, does NOT allow K8s service account
#           tokens to be used from outside the cluster via the Istio ingress-gateway.
#
kustomize build common/oauth2-proxy/overlays/m2m-dex-only/ | kubectl apply -f -
kubectl wait --for=condition=Ready pod -l 'app.kubernetes.io/name=oauth2-proxy' --timeout=180s -n oauth2-proxy
sleep 10
echo "Installing Dex..."
kustomize build common/dex/overlays/oauth2-proxy | kubectl apply -f -
kubectl wait --for=condition=Ready pods --all --timeout=180s -n auth
sleep 10
echo "Installing Knative Serving..."
kustomize build common/knative/knative-serving/overlays/gateways | kubectl apply -f -
kustomize build common/istio/cluster-local-gateway/base | kubectl apply -f -
sleep 10
echo "Installing Kubeflow Namespace..."
kustomize build common/kubeflow-namespace/base | kubectl apply -f -
echo "Installing Network Policies..."
kustomize build common/networkpolicies/base | kubectl apply -f -
sleep 10 
echo "Installing Kubeflow Roles..."
kustomize build common/kubeflow-roles/base | kubectl apply -f -

echo "Installing Istio Kubeflow Resources..."
kustomize build common/istio/kubeflow-istio-resources/base | kubectl apply -f -
sleep 10
echo "Installing Cert-Manager for multi-user..."
kustomize build applications/pipeline/upstream/env/cert-manager/platform-agnostic-multi-user | kubectl apply -f -
sleep 10
echo "Installing KServe..."
kustomize build applications/kserve/kserve | kubectl apply --server-side --force-conflicts -f -
kustomize build applications/kserve/models-web-app/overlays/kubeflow | kubectl apply -f -
sleep 10
echo "Installing Katib..."
kustomize build applications/katib/upstream/installs/katib-with-kubeflow | kubectl apply -f -
sleep 10
echo "Installing Central Dashboard..."
kustomize build applications/centraldashboard/overlays/oauth2-proxy | kubectl apply -f -
sleep 10
echo "Installing Admission Webhook with Cert-Manager..."
kustomize build applications/admission-webhook/upstream/overlays/cert-manager | kubectl apply -f -
sleep 10
echo "Installing Jupyter Notebook Controller and Jupyter Web App..."
kustomize build applications/jupyter/notebook-controller/upstream/overlays/kubeflow | kubectl apply -f -
sleep 20 
kustomize build applications/jupyter/jupyter-web-app/upstream/overlays/istio | kubectl apply -f -
sleep 10 
echo "Installing PVC Viewer..."
kustomize build applications/pvcviewer-controller/upstream/base | kubectl apply -f -
sleep 10
echo "Installing Profiles Controller..."
kustomize build applications/profiles/upstream/overlays/kubeflow | kubectl apply -f -
sleep 10
kustomize build applications/volumes-web-app/upstream/overlays/istio | kubectl apply -f -
echo "Installing TensorBoard..."
kustomize build applications/tensorboard/tensorboards-web-app/upstream/overlays/istio | kubectl apply -f -
sleep 10
kustomize build applications/tensorboard/tensorboard-controller/upstream/overlays/kubeflow | kubectl apply -f -
sleep 10
echo "Installing Training Operator..."
kustomize build applications/training-operator/upstream/overlays/kubeflow | kubectl apply --server-side --force-conflicts -f -
sleep 10
echo "Creating default profile..."
kustomize build common/user-namespace/base | kubectl apply -f -
sleep 10
echo "Kubeflow installation is complete!"
echo "kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80"
