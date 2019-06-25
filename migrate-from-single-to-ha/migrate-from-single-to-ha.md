# 手工迁移Mongo单副本集群到HA集群
## Part 1 
**注意：Part 1所有操作都在k8s master所在节点执行。**

前置条件：部署HA集群节点数必须大于等于3。一个shard分配的master，secondary和arbiter必须分布在不同节点。

```
docker exec -ti mongos_config0_1 bash
mongo --port=27018
use admin
db.auth("admin","E3xo9LYYUPZHtIRHaS7CD95s9MEP8PR2rksV78aAcJM=")
db.grantRolesToUser("admin", ["clusterAdmin"])
rs.status()
```
示例说明：本文中以一个原本使用2台机器部署的Mongo单副本集群作为示例。

部署shard0机器IP为10.40.80.40，部署shard1机器IP为10.40.80.40。

两台机器的mongodb的存储路径为/mnt/viid/mongodb。

### 1. 创建数据目录
````
sudo mkdir -p /mnt/viid/mongodb/replicaset1/db
sudo mkdir -p /mnt/viid/mongodb/replicaset1/configdb
````

### 2. 修改shard无认证启动
````
kubectl apply -f mongodb-maindb0-service-for-ha.yaml
kubectl apply -f mongodb-maindb1-service-for-ha.yaml
````
### 3. 启动replicaset
````
kubectl apply -f mongodb-replicaset-service.yaml
kubectl apply -f mongodb-replicaset1-service.yaml
````

### 4. 启动arbiter
````
kubectl apply -f mongodb-arbiter-service.yaml
kubectl apply -f mongodb-arbiter1-service.yaml
````

### 5. 进入 shard0 pod 执行以下命令。
````
kubectl exec -ti mongod-shard0-0 bash
use admin
db.createUser({user:"root",pwd:"root",roles:["root"]})
db.auth("root","root")
rs.add("mongod-replicaset0-0.mongodb-replicaset0-service.default.svc.cluster.local:27020")
rs.addArb("mongod-arbiter0-0.mongodb-arbiter0-service.default.svc.cluster.local:27021")
rs.conf()
````

### 6. 进入 shard1 pod 执行以下命令。如果有多个shard，则每个shard都需要执行类似以下操作。
````
use admin
db.createUser({user:"root",pwd:"root",roles:["root"]})
db.auth("root","root")
rs.add("mongod-replicaset1-0.mongodb-replicaset1-service.default.svc.cluster.local:27020")
rs.addArb("mongod-arbiter1-0.mongodb-arbiter1-service.default.svc.cluster.local:27021");
rs.conf()
````

### 7. 检查修改是否生效。非常重要！！
#### 检测1
````
kubectl exec -ti mongod-shard0-0 bash
mongo --port=27019
use admin
db.auth("root","root")
rs.status()
````
【示例附录1】

#### 检测2
执行以下命令，mongo client依然能读写数据

````
kubectl delete -f mongodb-maindb-service.yaml
````
【示例附录1】
````
shard0:SECONDARY> rs.status()
{
	"set" : "shard0",
	"date" : ISODate("2019-06-25T09:28:12.495Z"),
	"myState" : 2,
	"term" : NumberLong(6),
	"syncingTo" : "mongod-replicaset0-0.mongodb-replicaset0-service.default.svc.cluster.local:27020",
	"heartbeatIntervalMillis" : NumberLong(2000),
	"optimes" : {
		"lastCommittedOpTime" : {
			"ts" : Timestamp(1561454890, 1),
			"t" : NumberLong(6)
		},
		"readConcernMajorityOpTime" : {
			"ts" : Timestamp(1561454890, 1),
			"t" : NumberLong(6)
		},
		"appliedOpTime" : {
			"ts" : Timestamp(1561454890, 1),
			"t" : NumberLong(6)
		},
		"durableOpTime" : {
			"ts" : Timestamp(1561454890, 1),
			"t" : NumberLong(6)
		}
	},
	"members" : [
		{
			"_id" : 0,
			"name" : "mongod-shard0-0.mongodb-shard0-service.default.svc.cluster.local:27019",
			"health" : 1,
			"state" : 2,
			"stateStr" : "SECONDARY",
			"uptime" : 70947,
			"optime" : {
				"ts" : Timestamp(1561454890, 1),
				"t" : NumberLong(6)
			},
			"optimeDate" : ISODate("2019-06-25T09:28:10Z"),
			"syncingTo" : "mongod-replicaset0-0.mongodb-replicaset0-service.default.svc.cluster.local:27020",
			"configVersion" : 3,
			"self" : true
		},
		{
			"_id" : 1,
			"name" : "mongod-replicaset0-0.mongodb-replicaset0-service.default.svc.cluster.local:27020",
			"health" : 1,
			"state" : 1,
			"stateStr" : "PRIMARY",
			"uptime" : 70945,
			"optime" : {
				"ts" : Timestamp(1561454890, 1),
				"t" : NumberLong(6)
			},
			"optimeDurable" : {
				"ts" : Timestamp(1561454890, 1),
				"t" : NumberLong(6)
			},
			"optimeDate" : ISODate("2019-06-25T09:28:10Z"),
			"optimeDurableDate" : ISODate("2019-06-25T09:28:10Z"),
			"lastHeartbeat" : ISODate("2019-06-25T09:28:11.569Z"),
			"lastHeartbeatRecv" : ISODate("2019-06-25T09:28:11.568Z"),
			"pingMs" : NumberLong(0),
			"electionTime" : Timestamp(1561383747, 1),
			"electionDate" : ISODate("2019-06-24T13:42:27Z"),
			"configVersion" : 3
		},
		{
			"_id" : 2,
			"name" : "mongod-arbiter0-0.mongodb-arbiter0-service.default.svc.cluster.local:27021",
			"health" : 1,
			"state" : 7,
			"stateStr" : "ARBITER",
			"uptime" : 70945,
			"lastHeartbeat" : ISODate("2019-06-25T09:28:10.962Z"),
			"lastHeartbeatRecv" : ISODate("2019-06-25T09:28:10.962Z"),
			"pingMs" : NumberLong(0),
			"configVersion" : 3
		}
	],
	"ok" : 1,
	"operationTime" : Timestamp(1561454890, 1),
	"$gleStats" : {
		"lastOpTime" : Timestamp(0, 0),
		"electionId" : ObjectId("000000000000000000000000")
	},
	"$clusterTime" : {
		"clusterTime" : Timestamp(1561454890, 3),
		"signature" : {
			"hash" : BinData(0,"eNFV+lOsJ8OBnhvgac5tpPLuVkQ="),
			"keyId" : NumberLong("6705561868913606660")
		}
	},
	"$configServerState" : {
		"opTime" : {
			"ts" : Timestamp(1561454890, 3),
			"t" : NumberLong(6)
		}
	}
}
````