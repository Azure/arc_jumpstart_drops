#!/bin/bash
export clusterName="JumpstartAKS"
export resourceGroupName="Jumpstart-Kaito"
export KAITO_WORKSPACE_VERSION=0.4.4
export GPU_NODE_POOL_NAME="gpupool"
export namespace="kaito-workspace"
export GPU_NODE_SIZE="Standard_NC12s_v3"

# # Prep cluster for GPU operator
kubectl create ns gpu-operator
kubectl label --overwrite ns gpu-operator pod-security.kubernetes.io/enforce=privileged

# # Install GPU operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install \
    --wait \
    --generate-name \
    -n gpu-operator \
    --create-namespace \
    nvidia/gpu-operator

# Check if GPU operator is running
kubectl -n gpu-operator wait pod \
    --for=condition=Ready \
    -l app.kubernetes.io/component=gpu-operator \
    --timeout=300s

# Check for Nvidia runtimeclass
kubectl get runtimeclass nvidia

# Label the GPU nodes
kubectl get nodes \
    -l agentpool="${GPU_NODE_POOL_NAME}" \
    -o name | \
    xargs -I {} \
    kubectl label --overwrite {} apps=$GPU_NODE_POOL_NAME


# Install KAITO workspace controller
helm install $namespace  --set clusterName=$MY_CLUSTER --wait \
https://github.com/kaito-project/kaito/raw/gh-pages/charts/kaito/workspace-$KAITO_WORKSPACE_VERSION.tgz --namespace $namespace --create-namespace

# Check if KAITO workspace controller is running
kubectl -n $namespace wait pod \
    --for=condition=Ready \
    -l app.kubernetes.io/instance=$namespace \
    --timeout=300s


# Deploy a workspace with GPU
cat <<EOF | kubectl apply -f -
apiVersion: kaito.sh/v1alpha1
kind: Workspace
metadata:
  name: workspace-falcon-7b-instruct
resource:
  instanceType: "$GPU_NODE_SIZE"
  labelSelector:
    matchLabels:
      apps: $GPU_NODE_POOL_NAME
inference:
  preset:
    name: "falcon-7b-instruct"
EOF


# Wait for workspace to be ready for inference (condition WorkspaceSucceeded=true)
echo "Waiting for workspace to be ready..."
kubectl wait --for=condition=WorkspaceSucceeded=true workspace/workspace-falcon-7b-instruct --timeout=1500s

# Get the cluster IP to send a request to the inference service
export CLUSTERIP=$(kubectl get \
    svc workspace-falcon-7b-instruct \
    -o jsonpath="{.spec.clusterIPs[0]}")

# Ask the LLM a question
export QUESTION="What is Arc Jumpstart?"
kubectl run -it --rm --restart=Never curl --image=curlimages/curl -- curl -X POST http://$CLUSTERIP/v1/completions \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"falcon-7b-instruct\",
    \"prompt\": \"$QUESTION\",
    \"max_tokens\": 20,
    \"temperature\": 0
  }"