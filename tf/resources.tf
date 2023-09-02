provider "alicloud" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}


variable "name" {
  default = "chatGPT"
}

data "alicloud_zones" "zone" {
 available_resource_creation = "VSwitch"
}

resource "alicloud_vpc" "vpc" {
  vpc_name       = var.name
  cidr_block = "10.0.0.0/16"
}




///////////////////////////////////////////////////////////////

//database




resource "alicloud_vswitch" "dbvs1" {
  vswitch_name="dbvs1"
  vpc_id            = alicloud_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.alicloud_zones.zone.zones[0].id
  depends_on = [alicloud_vpc.vpc]
}
resource "alicloud_vswitch" "dbvs2" {
  vswitch_name="dbvs2"
  vpc_id            = alicloud_vpc.vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.alicloud_zones.zone.zones[1].id
  depends_on = [alicloud_vpc.vpc]
}

locals {
  dbvss = "${alicloud_vswitch.dbvs1.id},${alicloud_vswitch.dbvs2.id}"
}


resource "alicloud_db_instance" "mysqldb" {
  engine               = "MySQL"
  engine_version       = "5.7"
  instance_storage     = "30"
  instance_type        = "rds.mysql.t1.small"
  instance_charge_type = "Postpaid"
  instance_name        = var.name
  zone_id              = data.alicloud_zones.zone.zones[0].id
  zone_id_slave_a      = data.alicloud_zones.zone.zones[1].id
  vswitch_id           = local.dbvss
  monitoring_period    = "60"
  # security_ips         = ["192.168.96.0/19","192.168.64.0/19"]
  security_ips         = ["0.0.0.0/0"]
  connection_string_prefix="mysqlprivateconnectionstring"
}


resource "alicloud_db_account" "account" {
  instance_id = alicloud_db_instance.mysqldb.id
  name        = "test1"
  password    = "Password@1"
}

resource "alicloud_db_database" "db" {
  instance_id = alicloud_db_instance.mysqldb.id
  name        = "users"
}

resource "alicloud_db_account_privilege" "privilege" {
  instance_id  = alicloud_db_instance.mysqldb.id
  account_name = alicloud_db_account.account.name
  privilege    = "ReadWrite"
  db_names     = [alicloud_db_database.db.name]
}

resource "alicloud_db_connection" "connection" {
  instance_id       = alicloud_db_instance.mysqldb.id
  connection_prefix = "tf-example"
}

/////////////////////////////////////////////////////////////////

//redis


resource "alicloud_resource_manager_resource_group" "chatgpt_resource_group" {
  resource_group_name = "chatgptresourcegroup"
  display_name        = "chatgpt_resource_group"
}

resource "alicloud_security_group" "group" {
  name        = "alicloud_security_group"

  vpc_id      = alicloud_vpc.vpc.id
}


resource "alicloud_vswitch" "rdeisVs1" {
  vswitch_name="rdeisVs1"
  vpc_id            = alicloud_vpc.vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.alicloud_zones.zone.zones[0].id
  depends_on = [alicloud_vpc.vpc]
}


resource "alicloud_kvstore_instance" "redis" {
  db_instance_name  = "redis"

  vswitch_id        = alicloud_vswitch.rdeisVs1.id
  security_group_id = alicloud_security_group.group.id
  security_ips      = ["10.0.5.0/24","10.0.6.0/24"]
  #  security_ips      = ["0.0.0.0/0"]

  instance_type     = "Redis"
  engine_version    = "5.0"
  config = {
    appendonly             = "yes",
    lazyfree-lazy-eviction = "yes",
  }
  tags = {
    Created = "TF",
    For     = "Test",
  }
  resource_group_id = alicloud_resource_manager_resource_group.chatgpt_resource_group.id
  zone_id           = data.alicloud_zones.zone.zones[0].id
  secondary_zone_id = data.alicloud_zones.zone.zones[1].id

  instance_class = "redis.master.small.default"
  private_connection_prefix = "privateconnectionstringprefix"
}

resource "alicloud_kvstore_account" "redisAccount" {
  account_name     = "test1" 
  account_password = "Password@1"  
  instance_id      = alicloud_kvstore_instance.redis.id
  depends_on=[alicloud_kvstore_instance.redis]

}


///////////////////////////////////////////////////////////



//load balancer


resource "alicloud_vswitch" "dmz" {
  vswitch_name="dmz"
  vpc_id            = alicloud_vpc.vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = data.alicloud_zones.zone.zones[0].id
  depends_on = [alicloud_vpc.vpc]
}


resource "alicloud_slb_load_balancer" "load_balancer" {
  load_balancer_name = "chatgpr_load_balancer"
  address_type       = "internet"
  load_balancer_spec = "slb.s2.small"
  vswitch_id         = alicloud_vswitch.dmz.id
  instance_charge_type = "PayBySpec"

}










////////////////////////////////////////////////////////////


//output




output "slb_id" {
  value = alicloud_slb_load_balancer.load_balancer.id
}




//kubernetes





resource "alicloud_vswitch" "v1" {
  vpc_id            = alicloud_vpc.vpc.id
  cidr_block        = "10.0.5.0/24"
  zone_id           = data.alicloud_zones.zone.zones[0].id
  vswitch_name      = "V1"
}

resource "alicloud_vswitch" "v2" {
  vpc_id            = alicloud_vpc.vpc.id
  cidr_block        = "10.0.6.0/24"
  zone_id           = data.alicloud_zones.zone.zones[1].id
  vswitch_name      = "V2"
}




variable "k8s_name" {

 default     = "tf-ack"
}
variable "cluster_addons_flannel" {
  type = list(object({
    name      = string
    config    = string
  }))

  default = [
    {
      "name"     = "flannel",
      "config"   = "",
    },
    {
      "name"     = "logtail-ds",
      "config"   = "{\"IngressDashboardEnabled\":\"true\"}",
    },
    {
      "name"     = "nginx-ingress-controller",
      "config"   = "{\"IngressSlbNetworkType\":\"internet\"}",
    },
    {
      "name"     = "arms-prometheus",
      "config"   = "",
      "disabled": false,
    },
    {
      "name"     = "ack-node-problem-detector",
      "config"   = "{\"sls_project_name\":\"\"}",
      "disabled": false,
    },
    {
      "name"     = "csi-plugin",
      "config"   = "",
    },
    {
      "name"     = "csi-provisioner",
      "config"   = "",
    }
  ]
}

resource "random_uuid" "this" {}
# The default resource names. 
locals {
  k8s_name_flannel        = substr(join("-", [var.k8s_name,"flannel"]), 0, 63)
  k8s_name_ask            = substr(join("-", [var.k8s_name,"ask"]), 0, 63)
}


resource "alicloud_cs_managed_kubernetes" "flannel" {
  # The name of the cluster. 
  name                      = local.k8s_name_flannel
  # Create an ACK Pro cluster. 
  cluster_spec              = "ack.pro.small"
  version                   = "1.22.15-aliyun.1"
  # The vSwitches of the new Kubernetes cluster. Specify one or more vSwitch IDs. The vSwitches must be in the zone specified by availability_zone. 
  worker_vswitch_ids        = [alicloud_vswitch.v1.id,alicloud_vswitch.v2.id]

  # Specify whether to create a NAT gateway when the system creates the Kubernetes cluster. Default value: true. 
  new_nat_gateway           = true
  # The pod CIDR block. If you set cluster_network_type to flannel, this parameter is required. The pod CIDR block cannot be the same as the VPC CIDR block or the CIDR blocks of other Kubernetes clusters in the VPC. You cannot change the pod CIDR block after the cluster is created. Maximum number of hosts in the cluster: 256. 
  pod_cidr                  = "10.10.0.0/16"
  # The Service CIDR block. The Service CIDR block cannot be the same as the VPC CIDR block or the CIDR blocks of other Kubernetes clusters in the VPC. You cannot change the Service CIDR block after the cluster is created. 
  service_cidr              = "10.12.0.0/16"
  # Specify whether to create an Internet-facing Server Load Balancer (SLB) instance for the API server of the cluster. Default value: false. 
  slb_internet_enabled      = true

 

  # The logs of the control plane. 
  control_plane_log_components = ["apiserver", "kcm", "scheduler", "ccm"]

  # The components. 
dynamic "addons" {
    for_each = var.cluster_addons_flannel
    content {
      name     = lookup(addons.value, "name", var.cluster_addons_flannel)
      config   = lookup(addons.value, "config", var.cluster_addons_flannel)
      # disabled = lookup(addons.value, "disabled", var.cluster_addons_flannel)
    }
  }

  # The container runtime. 
  runtime = {
    name    = "docker"
    version = "19.03.15"
  }
}

resource "alicloud_cs_kubernetes_node_pool" "flannel" {
  # The name of the cluster. 
  cluster_id            = alicloud_cs_managed_kubernetes.flannel.id
  # The name of the node pool. 
  name                  = "default-nodepool"
  # The vSwitches of the new Kubernetes cluster. Specify one or more vSwitch IDs. The vSwitches must be in the zone specified by availability_zone. 
  vswitch_ids           = [alicloud_vswitch.v1.id,alicloud_vswitch.v2.id]

  # Worker ECS Type and ChargeType
  # instance_types      = [data.alicloud_instance_types.default.instance_types[0].id]
  instance_types         =  ["ecs.c6.xlarge"]


  # customize worker instance name
  # node_name_mode      = "customized,ack-flannel-shenzhen,ip,default"

  #Container Runtime
  runtime_name          = "docker"
  runtime_version       = "19.03.15"

  # The number of worker nodes in the Kubernetes cluster. Default value: 3. Maximum value: 50. 
  desired_size          = 2
  # The password that is used to log on to the cluster by using SSH. 
  password              = "Password@1"

  # Specify whether to install the CloudMonitor agent on the nodes in the cluster. 
  install_cloud_monitor = true

  # The type of the system disks of the nodes. Valid values: cloud_ssd and cloud_efficiency. Default value: cloud_efficiency. 
  system_disk_category  = "cloud_essd"
  system_disk_size      = 40

  # OS Type
  image_type            = "AliyunLinux"

  # Configurations of the data disks of the nodes. 
  data_disks {
    # The disk type. 
    category = "cloud_essd"
    # The disk size. 
    size     = 40
  }
}




