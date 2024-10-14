
function log {
    echo "$(date +"%Y-%m-%d %H:%M:%S %Z"): $@"
}

function logn {
    echo -n "$(date +"%Y-%m-%d %H:%M:%S %Z"): $@"
}

function is_required_tool_missed {
    logn "--> Checking required tool: $1 ... "
    if [ -x "$(command -v $1)" ]; then
        echo "installed"
        false
    else
        echo "NOT installed"
        true
    fi
}


# Firstly, let's do a quick check for required tools
missed_tools=0
log "Firstly, let's do a quick check for required tools ..."
# check docker
if is_required_tool_missed "docker"; then missed_tools=$((missed_tools+1)); fi
# check git
if is_required_tool_missed "git"; then missed_tools=$((missed_tools+1)); fi
# check cfssl
if is_required_tool_missed "cfssl"; then missed_tools=$((missed_tools+1)); fi
# check cfssljson
if is_required_tool_missed "cfssljson"; then missed_tools=$((missed_tools+1)); fi
# check kind
if is_required_tool_missed "kind"; then missed_tools=$((missed_tools+1)); fi
# check kubectl
if is_required_tool_missed "kubectl"; then missed_tools=$((missed_tools+1)); fi
# final check
if [[ $missed_tools > 0 ]]; then
  log "Abort! There are some required tools missing, please have a check."
  exit 98
fi


# Generating TLS for both Kubernetes and Dex
log "Generating TLS for both Kubernetes and Dex ..."
pushd tls-setup
make ca req-dex req-k8s
popd


# Creating Kubernetes cluster with API Server configured
log "Creating Kubernetes cluster with API Server configured ..."
PROJECT_ROOT="$(pwd)" envsubst < kind/kind.yaml | kind create cluster --name dex-cluster --config -

# Deploying Dex in namespace 'dex'
log "Deploying Dex in namespace 'dex' ..."
kubectl create ns dex
kubectl create secret tls dex-tls \
    --namespace dex \
    --cert=tls-setup/_certs/dex.pem \
    --key=tls-setup/_certs/dex-key.pem
kubectl apply --namespace dex -f dex/dex.yaml
kubectl wait --namespace dex --for=condition=ready pod -l app=dex


# Creating a proxy to access Dex directly from laptop
log "Creating a proxy to access Dex directly from laptop ..."
SVC_PORT="$(kubectl get -n dex svc/dex -o json | jq '.spec.ports[0].nodePort')"
docker run -d --restart always \
    --name dex-kind-proxy-$SVC_PORT \
    --publish 127.0.0.1:$SVC_PORT:$SVC_PORT \
    --link dex-cluster-control-plane:target \
    --network kind \
    alpine/socat -dd \
    tcp-listen:$SVC_PORT,fork,reuseaddr tcp-connect:target:$SVC_PORT
