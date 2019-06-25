kubectl create secret generic shared-bootstrap-data --from-file=internal-auth-mongodb-keyfile=key.file
kubectl apply -f mongodb-configdb-service.yaml
kubectl apply -f mongodb-maindb-service.yaml
kubectl apply -f mongodb-maindb1-service.yaml
kubectl apply -f mongodb-mongos-service.yaml