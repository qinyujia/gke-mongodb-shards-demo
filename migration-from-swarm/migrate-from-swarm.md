# 手工迁移Mongo单副本集群到K8s
## Part 1 

**注意：Part 1所有操作都在原来的swarm环境上执行。**

示例说明：本文中以一个原本使用2台机器部署的Mongo单副本集群作为示例。

部署shard0机器IP为10.40.80.146，部署shard1机器IP为10.40.80.148。

两台机器的mongodb的存储路径为/yitu/hdd1/viid/qinyujia/mongodb。

前置条件：给admin账号赋值集群权限。

````
docker exec -ti mongos_config0_1 bash
mongo --port=27018
use admin
db.auth("admin","E3xo9LYYUPZHtIRHaS7CD95s9MEP8PR2rksV78aAcJM=")
db.grantRolesToUser("admin", ["clusterAdmin"])
rs.status()
````
### 1. 停掉所有使用该Mongo集群的应用，包括视图的Gather，Consumer等。
### 2. 分别在每台部署机器上执行`docker-compose -f docker-compose.yml -p mongos down -v`停掉原来的服务。
### 3. 将 migrate-from-swarm 目录下的 docker-compose-migrate.yml 和 docker-compose-migrate-after.yml 拷贝到shard0机器上。
同样的将对应的docker-compose-migrate-N.yml和docker-compose-migrate-after-N.yml拷贝到shardN机器上。
### 4. 分别在每台部署机器上执行`docker-compose -f docker-compose-migrate.yml -p mongos up -d`启动服务。
### 5. 修改每个Shard replicaset配置。
#### 5.1 账号添加，在primary上执行。
````
use admin
db.createUser({user:"root",pwd:"root",roles:["root"]})
db.auth("root","root")
````
#### 5.2 shard0修改命令
````
docker exec -ti mongos_shard0_1 bash
mongo --port=37019
use local
cfg = db.system.replset.findOne( { "_id": "shard0" } )
cfg.members[0].host = "mongod-shard0-0.mongodb-shard0-service.default.svc.cluster.local:27019"
db.system.replset.update( { "_id": "shard0" } , cfg )
use admin
db.system.version.find()
db.system.version.update({"_id" : "shardIdentity"},{"$set":{"configsvrConnectionString" : "configserver/mongod-configdb-0.mongodb-configdb-service.default.svc.cluster.local:27018,mongod-configdb-1.mongodb-configdb-service.default.svc.cluster.local:27018"}})
db.system.version.find()
````
#### 5.2 shard1修改命令
````
docker exec -ti mongos_shard1_1 bash
mongo --port=37019
use local
cfg = db.system.replset.findOne( { "_id": "shard1" } )
cfg.members[0].host = "mongod-shard1-0.mongodb-shard1-service.default.svc.cluster.local:27019"
db.system.replset.update( { "_id": "shard1" } , cfg )
use admin
db.system.version.find()
db.system.version.update({"_id" : "shardIdentity"},{"$set":{"configsvrConnectionString" : "configserver/mongod-configdb-0.mongodb-configdb-service.default.svc.cluster.local:27018,mongod-configdb-1.mongodb-configdb-service.default.svc.cluster.local:27018"}})
db.system.version.find()
````

### 6. 修改每个ConfigServer replicaset配置。
````
docker exec -ti mongos_config0_1 bash
mongo --port=37018
````
#### 6.1 ConfigServer 修改命令
````
use local
cfg = db.system.replset.findOne( { "_id": "configserver" } )
cfg.members[0].host = "mongod-configdb-0.mongodb-configdb-service.default.svc.cluster.local:27018"
cfg.members[1].host = "mongod-configdb-1.mongodb-configdb-service.default.svc.cluster.local:27018"
db.system.replset.update( { "_id": "configserver" } , cfg )
use config
cfg=db.shards.findOne({_id:'shard0'})
cfg.host="shard0/mongod-shard0-0.mongodb-shard0-service.default.svc.cluster.local:27019"
db.shards.update({_id:'shard0'},cfg)
cfg=db.shards.findOne({_id:'shard0'})
cfg=db.shards.findOne({_id:'shard1'})
cfg.host="shard1/mongod-shard1-0.mongodb-shard1-service.default.svc.cluster.local:27019"
db.shards.update({_id:'shard1'},cfg)
cfg=db.shards.findOne({_id:'shard1'})
````

### 7. 分别在每台部署机器上执行 `docker-compose -f docker-compose-migrate.yml -p mongos down -v` 停止服务。
### 8. 分别在每台部署机器上执行 `docker-compose -f docker-compose-migrate-after.yml -p mongos up -d` 启动服务。
### 9. 检查修改是否生效。非常重要！！
#### 9.1 使用原来的admin账号密码连接router，可以验证成功，并且表里的数据能正常显示。
#### 9.2 检查每个ConfigServer replicaset。
````
docker exec -ti mongos_config0_1 bash
mongo --port=27018
use admin
db.auth("admin","nuhLYsJazVzEh5LJVWJ2zFfKN6vPQUYKjtwEoJuVnxg=")
rs.status()
````
##### 输出示例
【示例附录1】
##### 只在primary上执行sh.status()
【示例附录2】
#### 9.3 检查每个Shard replicaset。
docker exec -ti mongos_shard0_1 bash
mongo --port=27019
【示例附录3】
### 10. 分别在每台部署机器上执行 `docker-compose -f docker-compose-migrate-after.yml -p mongos down -v` 停止服务。

# Part 2
**注意：Part 2除了拷贝数据之外的所有操作都在k8s集群指定部署Mongo集群的2台机器上执行。**

示例说明：本文中以一个原本使用2台机器部署的Mongo单副本集群作为示例。

两台机器的mongodb的存储路径为/mnt/viid/mongodb。

两个节点分别为wxec0052(10.40.80.40)，wxec0053(10.40.80.41)。可以通过kubectl get nodes获取节点名称。规划shard0分片迁移到wxec0052上，shard1分片迁移到wxec0053上。

## 1. 拷贝数据。
在 10.40.80.146 上执行。同样的在 10.40.80.148 上依次执行以下类似操作。

````
cd /yitu/hdd1/viid/qinyujia
sudo tar -czf 10.40.80.146.tar.gz mongodb
scp 10.40.80.146.tar.gz yjqin@10.40.80.40:~
````
## 2. 创建数据目录。
在 10.40.80.40 上执行。同样的在 10.40.80.41 上依次执行以下类似操作（shard0需要换成shard1）。

````
sudo mkdir -p /mnt/viid/mongodb/shard0/data/db
sudo mkdir -p /mnt/viid/mongodb/shard0/data/configdb
sudo mkdir -p /mnt/viid/mongodb/config/data/db
sudo mkdir -p /mnt/viid/mongodb/config/data/configdb
sudo mkdir -p /mnt/viid/mongodb/router/data/db
sudo mkdir -p /mnt/viid/mongodb/router/data/configdb
````
## 3. 复制数据到指定目录。
在 10.40.80.40 上执行。同样的在 10.40.80.41 上依次执行以下类似操作（shard0需要换成shard1）。

````
tar -xzvf 10.40.80.146.tar.gz
cd ~/mongodb
sudo cp -r config0/* /mnt/viid/mongodb/config
sudo cp -r router0/* /mnt/viid/mongodb/router
sudo cp -r shard0/* /mnt/viid/mongodb/shard0
````
## 4. 在resources目录下创建文件key.file,把admin的密码存入key.file中。
## 5. 执行resources目录下的create.sh脚本。
## 6. 检查修改是否生效。非常重要！！
### 6.1 检查pods状态。
执行 kubectl get pods。每个pod的状态都是running。
【示例附录4】
### 6.2 使用原来的admin账号密码连接router，可以验证成功，并且表里的数据能正常显示。

本示例的mongo连接地址是10.40.80.41:30017

**注意：以下检查命令在kubectl安装机器上执行，或者在k8s master机器上执行。**
### 6.3 检查每个ConfigServer replicaset。

````
kubectl exec -ti mongod-configdb-0 bash
mongo --port=27018
use admin
db.auth("admin","nuhLYsJazVzEh5LJVWJ2zFfKN6vPQUYKjtwEoJuVnxg=")
rs.status()
````
#### 输出示例
【示例附录1】
#### 只在primary上执行sh.status()
【示例附录2】
### 6.4 检查每个Shard replicaset。

````
kubectl exec -ti mongod-shard0-0 bash
mongo --port=27019
use admin
db.auth("root","root")
rs.status()
````
【示例附录3】

【示例附录1】

````
{
	"set" : "configserver",
	"date" : ISODate("2019-06-25T03:44:09.193Z"),
	"myState" : 1,
	"term" : NumberLong(4),
	"configsvr" : true,
	"heartbeatIntervalMillis" : NumberLong(2000),
	"optimes" : {
		"lastCommittedOpTime" : {
			"ts" : Timestamp(1561434246, 1),
			"t" : NumberLong(4)
		},
		"readConcernMajorityOpTime" : {
			"ts" : Timestamp(1561434246, 1),
			"t" : NumberLong(4)
		},
		"appliedOpTime" : {
			"ts" : Timestamp(1561434246, 1),
			"t" : NumberLong(4)
		},
		"durableOpTime" : {
			"ts" : Timestamp(1561434246, 1),
			"t" : NumberLong(4)
		}
	},
	"members" : [
		{
			"_id" : 0,
			"name" : "mongod-configdb-0.mongodb-configdb-service.default.svc.cluster.local:27018",
			"health" : 1,
			"state" : 1,
			"stateStr" : "PRIMARY",
			"uptime" : 241,
			"optime" : {
				"ts" : Timestamp(1561434246, 1),
				"t" : NumberLong(4)
			},
			"optimeDate" : ISODate("2019-06-25T03:44:06Z"),
			"electionTime" : Timestamp(1561434020, 1),
			"electionDate" : ISODate("2019-06-25T03:40:20Z"),
			"configVersion" : 1,
			"self" : true
		},
		{
			"_id" : 1,
			"name" : "mongod-configdb-1.mongodb-configdb-service.default.svc.cluster.local:27018",
			"health" : 1,
			"state" : 2,
			"stateStr" : "SECONDARY",
			"uptime" : 229,
			"optime" : {
				"ts" : Timestamp(1561434246, 1),
				"t" : NumberLong(4)
			},
			"optimeDurable" : {
				"ts" : Timestamp(1561434246, 1),
				"t" : NumberLong(4)
			},
			"optimeDate" : ISODate("2019-06-25T03:44:06Z"),
			"optimeDurableDate" : ISODate("2019-06-25T03:44:06Z"),
			"lastHeartbeat" : ISODate("2019-06-25T03:44:08.952Z"),
			"lastHeartbeatRecv" : ISODate("2019-06-25T03:44:09.084Z"),
			"pingMs" : NumberLong(0),
			"syncingTo" : "mongod-configdb-0.mongodb-configdb-service.default.svc.cluster.local:27018",
			"configVersion" : 1
		}
	],
	"ok" : 1,
	"operationTime" : Timestamp(1561434246, 1),
	"$gleStats" : {
		"lastOpTime" : Timestamp(0, 0),
		"electionId" : ObjectId("7fffffff0000000000000004")
	},
	"$clusterTime" : {
		"clusterTime" : Timestamp(1561434246, 1),
		"signature" : {
			"hash" : BinData(0,"AAAAAAAAAAAAAAAAAAAAAAAAAAA="),
			"keyId" : NumberLong(0)
		}
	}
}
````

【示例附录2】

````
configserver:PRIMARY> sh.status()
--- Sharding Status ---
  sharding version: {
  	"_id" : 1,
  	"minCompatibleVersion" : 5,
  	"currentVersion" : 6,
  	"clusterId" : ObjectId("5d0ef0fd5a75b06790f91ca4")
  }
  shards:
        {  "_id" : "shard0",  "host" : "shard0/mongod-shard0-0.mongodb-shard0-service.default.svc.cluster.local:27019",  "state" : 1 }
        {  "_id" : "shard1",  "host" : "shard1/mongod-shard1-0.mongodb-shard1-service.default.svc.cluster.local:27019",  "state" : 1 }
  active mongoses:
        "3.6.4" : 2
  autosplit:
        Currently enabled: yes
  balancer:
        Currently enabled:  yes
        Currently running:  unknown
        Failed balancer rounds in last 5 attempts:  1
        Last reported error:  Could not find host matching read preference { mode: "primary" } for set shard0
        Time of Reported error:  Sun Jun 23 2019 20:32:40 GMT+0800 (HKT)
        Migration Results for the last 24 hours:
                No recent migrations
  databases:
        {  "_id" : "config",  "primary" : "config",  "partitioned" : true }
                config.system.sessions
                        shard key: { "_id" : 1 }
                        unique: false
                        balancing: true
                        chunks:
                                shard0	1
                        { "_id" : { "$minKey" : 1 } } -->> { "_id" : { "$maxKey" : 1 } } on : shard0 Timestamp(1, 0)
        {  "_id" : "viid",  "primary" : "shard0",  "partitioned" : true }
                viid.face
                        shard key: { "jpaShotTime" : 1, "jpaDeviceID" : 1 }
                        unique: false
                        balancing: true
                        chunks:
                                shard0	1
                        { "jpaShotTime" : { "$minKey" : 1 }, "jpaDeviceID" : { "$minKey" : 1 } } -->> { "jpaShotTime" : { "$maxKey" : 1 }, "jpaDeviceID" : { "$maxKey" : 1 } } on : shard0 Timestamp(1, 0)
                viid.imageInfo
                        shard key: { "jpaShotTime" : 1, "jpaDeviceID" : 1 }
                        unique: false
                        balancing: true
                        chunks:
                                shard0	1
                        { "jpaShotTime" : { "$minKey" : 1 }, "jpaDeviceID" : { "$minKey" : 1 } } -->> { "jpaShotTime" : { "$maxKey" : 1 }, "jpaDeviceID" : { "$maxKey" : 1 } } on : shard0 Timestamp(1, 0)
                viid.motorVehicle
                        shard key: { "jpaShotTime" : 1, "jpaDeviceID" : 1 }
                        unique: false
                        balancing: true
                        chunks:
                                shard0	1
                        { "jpaShotTime" : { "$minKey" : 1 }, "jpaDeviceID" : { "$minKey" : 1 } } -->> { "jpaShotTime" : { "$maxKey" : 1 }, "jpaDeviceID" : { "$maxKey" : 1 } } on : shard0 Timestamp(1, 0)
                viid.nonMotorVehicle
                        shard key: { "jpaShotTime" : 1, "jpaDeviceID" : 1 }
                        unique: false
                        balancing: true
                        chunks:
                                shard0	1
                        { "jpaShotTime" : { "$minKey" : 1 }, "jpaDeviceID" : { "$minKey" : 1 } } -->> { "jpaShotTime" : { "$maxKey" : 1 }, "jpaDeviceID" : { "$maxKey" : 1 } } on : shard0 Timestamp(1, 0)
                viid.person
                        shard key: { "jpaShotTime" : 1, "jpaDeviceID" : 1 }
                        unique: false
                        balancing: true
                        chunks:
                                shard0	1
                        { "jpaShotTime" : { "$minKey" : 1 }, "jpaDeviceID" : { "$minKey" : 1 } } -->> { "jpaShotTime" : { "$maxKey" : 1 }, "jpaDeviceID" : { "$maxKey" : 1 } } on : shard0 Timestamp(1, 0)
                viid.videoSliceInfo
                        shard key: { "jpaShotTime" : 1, "jpaDeviceID" : 1 }
                        unique: false
                        balancing: true
                        chunks:
                                shard0	1
                        { "jpaShotTime" : { "$minKey" : 1 }, "jpaDeviceID" : { "$minKey" : 1 } } -->> { "jpaShotTime" : { "$maxKey" : 1 }, "jpaDeviceID" : { "$maxKey" : 1 } } on : shard0 Timestamp(1, 0)
````                        
                        
【示例附录3】

````
shard0:PRIMARY> rs.status()
{
	"set" : "shard0",
	"date" : ISODate("2019-06-25T04:03:47.903Z"),
	"myState" : 1,
	"term" : NumberLong(4),
	"heartbeatIntervalMillis" : NumberLong(2000),
	"optimes" : {
		"lastCommittedOpTime" : {
			"ts" : Timestamp(1561435425, 1),
			"t" : NumberLong(4)
		},
		"readConcernMajorityOpTime" : {
			"ts" : Timestamp(1561435425, 1),
			"t" : NumberLong(4)
		},
		"appliedOpTime" : {
			"ts" : Timestamp(1561435425, 1),
			"t" : NumberLong(4)
		},
		"durableOpTime" : {
			"ts" : Timestamp(1561435425, 1),
			"t" : NumberLong(4)
		}
	},
	"members" : [
		{
			"_id" : 0,
			"name" : "mongod-shard0-0.mongodb-shard0-service.default.svc.cluster.local:27019",
			"health" : 1,
			"state" : 1,
			"stateStr" : "PRIMARY",
			"uptime" : 1419,
			"optime" : {
				"ts" : Timestamp(1561435425, 1),
				"t" : NumberLong(4)
			},
			"optimeDate" : ISODate("2019-06-25T04:03:45Z"),
			"electionTime" : Timestamp(1561434023, 1),
			"electionDate" : ISODate("2019-06-25T03:40:23Z"),
			"configVersion" : 1,
			"self" : true
		}
	],
	"ok" : 1,
	"operationTime" : Timestamp(1561435425, 1),
	"$gleStats" : {
		"lastOpTime" : Timestamp(0, 0),
		"electionId" : ObjectId("7fffffff0000000000000004")
	},
	"$clusterTime" : {
		"clusterTime" : Timestamp(1561435425, 1),
		"signature" : {
			"hash" : BinData(0,"AAAAAAAAAAAAAAAAAAAAAAAAAAA="),
			"keyId" : NumberLong(0)
		}
	},
	"$configServerState" : {
		"opTime" : {
			"ts" : Timestamp(1561435422, 1),
			"t" : NumberLong(4)
		}
	}
}
````

【示例附录4】

````
yjqin@WXEC0053:~/k8s/qinyujia/gke-mongodb-shards-demo/resources$ kubectl get pods
NAME                           READY   STATUS    RESTARTS   AGE
mongod-arbiter0-0              1/1     Running   0          18h
mongod-arbiter1-0              1/1     Running   0          18h
mongod-configdb-0              1/1     Running   0          41h
mongod-configdb-1              1/1     Running   0          41h
mongod-replicaset0-0           1/1     Running   0          17h
mongod-replicaset1-0           1/1     Running   0          17h
mongod-shard0-0                1/1     Running   0          17h
mongod-shard1-0                1/1     Running   0          41h
mongos-router-0                1/1     Running   0          39h
mongos-router-1                1/1     Running   0          39h
viid-gather-8648845d59-bqr2q   1/1     Running   0          6d3h
viid-gather-8648845d59-zg84q   1/1     Running   0          6d3h
````