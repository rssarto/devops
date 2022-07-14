#!/bin/bash
export ARGOCD_NAMESPACE='argocd'
wait-pods-in-namespace(){
  ALL_PODS_RUNNING=false
  IFS=$'\n'
  while [[ $ALL_PODS_RUNNING = false ]]; do
    declare -a NAMESPACE_PODS
    NAMESPACE_PODS=$(kubectl get pods -n $1 | awk '(NR>1)')
    for pod in "${NAMESPACE_PODS[@]}"
    do
      check_running=$(echo "$(echo "$pod" | grep "Running")" | grep "1/1")
      if [[ -z "$check_running" ]]; then
        ALL_PODS_RUNNING=false
        echo "Pod not running yet: $pod"
        break
      fi
      ALL_PODS_RUNNING=true
    done
    if [[ $ALL_PODS_RUNNING = false ]]; then
      echo "waiting..."     
      sleep 2
    fi
  done
  unset IFS
}
wait-for-resource(){
  local resourceCommand=$1
  local retryCount=${2:-100}
  for ((i = 0 ; i < $retryCount ; i++)); do
    resource=$(echo "$(eval $resourceCommand)" | awk '(NR > 1)')
    if [[ ! -z "$resource" ]]; then
      echo "Resource found: $resource"	    
      break
    fi
    echo "No resource found with command $resourceCommand"
    sleep 2
  done
}

argocd-install(){
  kubectl apply -f ./nginx-ingress.yaml
  echo
  echo "Installed nginx ingress"
  echo
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml
  #kubectl get pods -n metallb-system --watch
  wait-pods-in-namespace 'metallb-system'
  echo
  echo "Installed metallb L2 network load balancer."
  echo
  kubectl apply -f ./metallb-configmap.yaml
  echo
  echo "Defined IP pool for load balancer."
  echo
  kubectl create namespace $ARGOCD_NAMESPACE
  echo 
  echo "Created $ARGOCD_NAMESPACE namespace."
  echo
  kubectl apply -n $ARGOCD_NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  echo
  echo "Applied argocd deployment manifest."
  echo
  wait-pods-in-namespace 'argocd'
  kubectl apply -f ./lb-argocd-server.yaml
  echo
  echo "Created argocd loadbalancer."
  LPIP="$(kubectl get svc/lb-argocd-server-service -n ingress-nginx -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  if [[ -z "$LPIP" ]]; then
    echo "Load balancer ip not defined."
    return 1
  else
    echo "Load balancer ip is: $LPIP. You can map this ip address to your /etc/hosts file."
  fi
  echo
  kubectl apply -f ./self-signed-cluster-issuer.yaml
  echo
  echo "Created Cluster Self signed issuer"
  echo
  kubectl apply -f ./self-signed-certificate.yaml
  echo
  echo "Created Self signed certificate"
  echo
  kubectl apply -f ./argocd-ingress.yaml
  echo
  echo "Created argocd ingress rule"
  echo
  kubectl apply -n $ARGOCD_NAMESPACE -f ./argocd-ingress.yaml
  echo
  echo "Applied argocd ingress deployment"
  echo
  wait-for-resource 'kubectl -n argocd get secret argocd-initial-admin-secret'
  ARGOCD_ADMIN_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
  echo "ArgoCd admin password is: $ARGOCD_ADMIN_PASSWORD"
}

argocd-remove(){
  kubectl delete -n $ARGOCD_NAMESPACE -f ./argocd-ingress.yaml
  echo
  echo "Deleted argocd ingress deployment"
  echo
  kubectl delete -f ./self-signed-certificate.yaml
  echo
  echo "Deleted Self signed certificate"
  echo
  kubectl delete -f ./self-signed-cluster-issuer.yaml
  echo
  echo "Deleted Cluster Self signed issuer"
  echo
  kubectl delete -f ./lb-argocd-server.yaml
  echo
  echo "Deleted argocd loadbalancer."
  kubectl delete -n $ARGOCD_NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  echo
  echo "Deleted argocd deployment manifest."
  echo
  kubectl delete namespace $ARGOCD_NAMESPACE
  echo
  echo "Deleted $ARGOCD_NAMESPACE namespace"
  echo
  kubectl delete -f ./metallb-configmap.yaml
  echo
  echo "Deleted IP pool for load balancer."
  echo
  kubectl delete -f ./nginx-ingress.yaml
  echo
  echo "Deleted nginx ingress"
  echo
  kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml
  echo
  echo "Deleted metallb L2 network load balancer."
  echo
}

