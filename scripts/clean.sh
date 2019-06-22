#!/bin/sh
tree /mnt/viid/mongodb/
kubectl delete statefulsets mongos-router
kubectl delete services mongos-router-service
kubectl delete services mongos-router-service-nodeport
kubectl delete statefulsets mongod-shard0
kubectl delete services mongodb-shard0-service
kubectl delete statefulsets mongod-shard1
kubectl delete services mongodb-shard1-service
kubectl delete statefulsets mongod-configdb
kubectl delete services mongodb-configdb-service
kubectl delete secret shared-bootstrap-data
sudo rm -rf /mnt/viid/mongodb/config/data/configdb/*
sudo rm -rf /mnt/viid/mongodb/shard0/data/db/*
sudo rm -rf /mnt/viid/mongodb/shard1/data/db/*
tree /mnt/viid/mongodb
