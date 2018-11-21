resource "azurerm_resource_group" "trustedk8s" {
  name     = "${var.prefix}trustedk8s"
  location = "${var.location}"
  tags {
    environment = "${var.prefix}"
  }
}

# Azure LogAnalytics to visualize Kubernetes logs
resource "azurerm_log_analytics_workspace" "trustedk8s" {
  name                = "${var.prefix}trustedk8s"
  location            = "eastus"
  resource_group_name = "${azurerm_resource_group.trustedk8s.name}"
  sku                 = "Standard"
  retention_in_days   = 30
}

resource "azurerm_storage_account" "trustedk8s" {
    name                     = "${azurerm_resource_group.trustedk8s.name}"
    resource_group_name      = "${azurerm_resource_group.trustedk8s.name}"
    location                 = "${var.location}"
    account_tier             = "Standard"
    account_replication_type = "GRS"
    depends_on               = ["azurerm_resource_group.trustedk8s"]
    tags {
        environment = "${var.prefix}"
    }
}

resource "azurerm_kubernetes_cluster" "trustedk8s" {
  depends_on             = ["azurerm_subnet.trustedk8s"]
  name                   = "${azurerm_resource_group.trustedk8s.name}"
  location               = "${azurerm_resource_group.trustedk8s.location}"
  dns_prefix             = "${var.prefix}"
  resource_group_name    = "${azurerm_resource_group.trustedk8s.name}"
  kubernetes_version     = "1.11.4"

  agent_pool_profile {
    name    = "trustedk8s"
    count   = "1"
    vm_size = "Standard_D4s_v3"
    os_type = "Linux"
    vnet_subnet_id = "${azurerm_subnet.trustedk8s.id}" # ! Only one AKS per subnet
    os_disk_size_gb = 30 # It seems that terraform force a resource re-creation if size is not defined
  }

  linux_profile {
    admin_username = "azureuser"

    ssh_key {
      key_data = "${file("${var.ssh_pubkey_path}")}"
    }
  }

  network_profile {
    network_plugin     = "kubenet"
    service_cidr       = "10.128.0.0/16" # Number of IPs needed  = (number of nodes) + (number of nodes * pods per node)
    dns_service_ip     = "10.128.0.10" # Must be in service_cidr range
    docker_bridge_cidr = "172.17.0.1/16"
  }

  addon_profile {
    oms_agent {
      enabled = "true"
      log_analytics_workspace_id = "${ azurerm_log_analytics_workspace.trustedk8s.id }"
    }
  }

  service_principal {
    client_id     = "${var.client_id}"
    client_secret = "${var.client_secret}"
  }

  tags {
    environment = "${var.prefix}"
    location    = "${azurerm_resource_group.trustedk8s.location}"
  }
}

# Public IP used by the loadbalancer gw
resource "azurerm_public_ip" "trustedk8s" {
  depends_on                   = ["azurerm_kubernetes_cluster.trustedk8s"]
  name                         = "${var.prefix}gw-trustedk8s"
  location                     = "${var.location}"
  resource_group_name          = "MC_${azurerm_resource_group.trustedk8s.name}_${azurerm_kubernetes_cluster.trustedk8s.name}_${azurerm_kubernetes_cluster.trustedk8s.location}"
  public_ip_address_allocation = "Static"
  idle_timeout_in_minutes      = 30
  tags {
    environment = "${var.prefix}"
  }
}

