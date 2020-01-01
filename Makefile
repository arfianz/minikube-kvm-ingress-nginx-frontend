PHONY: frontend ingress

clean:
        minikube delete

start:
        minikube start --vm-driver=kvm2 --extra-config=apiserver.service-node-port-range=1-30000

ingress:
        kubectl apply -f ingress

frontend:
        kubectl apply -f frontend

all:
        kubectl apply -R -f .

list:
        minikube service list

watch:
        kubectl get pods -A --watch
