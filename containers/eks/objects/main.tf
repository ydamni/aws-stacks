### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "containers/eks/objects/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

### Kubernetes resources

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_service" "aws-stacks-kube-service-mysql" {
  metadata {
    name = "mysql"
    labels = {
      app = "mysql"
    }
  }

  spec {
    selector = {
      app = "mysql"
    }

    type = "ClusterIP"

    port {
      port = 3306
    }
  }
}

resource "kubernetes_deployment" "aws-stacks-kube-deployment-mysql" {
  metadata {
    name = "mysql"
    labels = {
      app = "mysql"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "mysql"
      }
    }

    template {
      metadata {
        labels = {
          app = "mysql"
        }
      }

      spec {
        container {
          name  = "mysql"
          image = "mysql:latest"

          port {
            container_port = 3306
          }

          env {
            name  = "MYSQL_ROOT_PASSWORD"
            value = var.mysql_root_password
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "aws-stacks-kube-service-phpmyadmin" {
  metadata {
    name = "phpmyadmin"
    labels = {
      app = "phpmyadmin"
    }
  }

  spec {
    selector = {
      app = "phpmyadmin"
    }

    type = "LoadBalancer"

    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_deployment" "aws-stacks-kube-deployment-phpmyadmin" {
  metadata {
    name = "phpmyadmin"
    labels = {
      app = "phpmyadmin"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "phpmyadmin"
      }
    }

    template {
      metadata {
        labels = {
          app = "phpmyadmin"
        }
      }

      spec {
        container {
          name  = "phpmyadmin"
          image = "phpmyadmin:latest"

          port {
            container_port = 80
          }

          env {
            name  = "PMA_HOST"
            value = "mysql"
          }

          env {
            name  = "PMA_USER"
            value = "root"
          }

          env {
            name  = "PMA_PASSWORD"
            value = var.mysql_root_password
          }
        }
      }
    }
  }
}
