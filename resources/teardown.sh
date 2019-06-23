#!/bin/sh
##
# Script to remove/undepoy all project resources for mongo cluster.
##

# Delete mongos stateful set + mongod stateful set + mongodb service + secrets
kubectl delete statefulsets mongos-router
kubectl delete services mongos-router-service
kubectl delete services mongos-router-service-nodeport
kubectl delete statefulsets mongod-shard0
kubectl delete services mongodb-shard0-service
kubectl delete statefulsets mongod-shard1
kubectl delete services mongodb-shard1-service
kubectl delete statefulsets mongod-configdb
kubectl delete services mongodb-configdb-service
#kubectl delete secret shared-bootstrap-data
#sleep 3

#clean all the disks
#bash /home/yjqin/k8s/qinyujia/cleanVolume.sh

# Delete GCE disks
#for i in 1 2 3
#do
#    gcloud -q compute disks delete pd-ssd-disk-4g-$i
#done

