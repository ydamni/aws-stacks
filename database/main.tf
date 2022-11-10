### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "database/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

### Get VPC & Subnets

data "aws_vpc" "aws-stacks-vpc" {
  filter {
    name   = "tag:Name"
    values = ["aws-stacks-vpc"]
  }
}

data "aws_subnets" "aws-stacks-subnets" {
  filter {
    name = "tag:Name"
    values = [
      "aws-stacks-subnet-public-1",
      "aws-stacks-subnet-public-2",
      "aws-stacks-subnet-public-3"
    ]
  }
}

### Security Groups

data "aws_security_group" "aws-stacks-sg-ec2" {
  filter {
    name = "tag:Name"
    values = [
      "aws-stacks-sg-ec2"
    ]
  }
}

resource "aws_security_group" "aws-stacks-sg-rds" {
  name        = "aws-stacks-sg-rds"
  description = "Only EC2 instances can access RDS DB"
  vpc_id      = data.aws_vpc.aws-stacks-vpc.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    security_groups = [
      data.aws_security_group.aws-stacks-sg-ec2.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "aws-stacks-sg-rds"
  }
}

### RDS resources

resource "aws_db_subnet_group" "aws-stacks-rds-db-subnet-group" {
  name       = "aws-stacks-rds-db-subnet-group"
  subnet_ids = [data.aws_subnets.aws-stacks-subnets.ids[0], data.aws_subnets.aws-stacks-subnets.ids[1], data.aws_subnets.aws-stacks-subnets.ids[2]]

  tags = {
    Name = "aws-stacks-rds-db-subnet-group"
  }
}

resource "aws_db_instance" "aws-stacks-rds-db-instance" {
  identifier                 = "aws-stacks-rds-db-instance"
  engine                     = "mysql"
  engine_version             = "8.0.28"
  instance_class             = "db.t3.micro"
  multi_az                   = true
  allocated_storage          = 5
  storage_type               = "standard"
  storage_encrypted          = false
  username                   = var.db_admin_username
  password                   = var.db_admin_password
  db_name                    = "computer_store"
  parameter_group_name       = "default.mysql8.0"
  skip_final_snapshot        = true
  auto_minor_version_upgrade = false
  db_subnet_group_name       = aws_db_subnet_group.aws-stacks-rds-db-subnet-group.name
  vpc_security_group_ids     = [aws_security_group.aws-stacks-sg-rds.id]
}

### Get EC2 instances

data "aws_instances" "aws-stacks-ec2-instances" {
  filter {
    name   = "tag:Name"
    values = ["aws-stacks-asg"]
  }
}

### Get SSH Key

data "local_file" "aws-stacks-file-key" {
  filename = "${path.module}/aws-stacks-ec2-access-key.pem"
}

### Remote Exec

# Configure Database

resource "local_file" "aws-stacks-file-sql" {
  filename = "${path.module}/aws-stacks-config-db.sql"
  content  = <<EOF
CREATE USER '${var.db_reader_username}' IDENTIFIED BY '${var.db_reader_password}';
GRANT SELECT, SHOW VIEW ON computer_store.* TO reader;
CREATE TABLE products(id INT PRIMARY KEY NOT NULL AUTO_INCREMENT, name VARCHAR(100), category VARCHAR(100), price DOUBLE, stock INT);
CREATE TABLE customers (id INT PRIMARY KEY NOT NULL AUTO_INCREMENT, first_name VARCHAR(100), last_name VARCHAR(100), age INT, email VARCHAR(100));
CREATE TABLE orders (id INT PRIMARY KEY NOT NULL AUTO_INCREMENT, customer_id INT, product_id INT, order_date DATE, cost DOUBLE);
INSERT INTO products (name, category, price, stock) VALUES ('Superkey 84', 'keyboard', 50, 7), ('MX Click', 'mouse', 39, 2), ('Type Pro 2022', 'keyboard', 115, 4), ('GL Zoom', 'webcam', 70, 13), ('LEDD Future 5K', 'monitor', 450, 1);
INSERT INTO customers (first_name, last_name, age, email) VALUES ('James', 'Cooper', 27, 'james.cooper@cif-mail.com'), ('Ruth', 'Dugan', 45, 'ruth.dugan@cif-mail.com'), ('Victor', 'Jackson', 14, 'victor.jackson@cif-mail.com'), ('Elizabeth', 'Sullivan', 27, 'elizabeth.sullivan@cif-mail.com'), ('Connie', 'Jackson', 33, 'connie.jackson@cif-mail.com');
INSERT INTO orders(customer_id, product_id, order_date, cost) VALUES (1, 3, '2022-01-02', 115), (1, 5, '2022-01-02', 450), (3, 4, '2022-01-12', 70), (2, 4, '2022-01-17', 70), (1, 1, '2022-02-01', 50), (4, 2, '2022-02-14', 39), (4, 3, '2022-02-27', 115), (5, 3, '2022-02-28', 115), (1, 3, '2022-03-03', 115), (2, 1, '2022-03-18', 50);
EOF
}

resource "null_resource" "aws-stacks-configure-database" {

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(data.local_file.aws-stacks-file-key.filename)
    host        = data.aws_instances.aws-stacks-ec2-instances.public_ips[0]
  }

  provisioner "file" {
    source      = local_file.aws-stacks-file-sql.filename
    destination = "/tmp/aws-stacks-config-db.sql"
  }

  provisioner "remote-exec" {
    inline = [
      ### Install MySQL CLI
      "sudo yum -y update",
      "sudo yum -y install mysql",
      ### Configure RDS DB
      "mysql -h ${aws_db_instance.aws-stacks-rds-db-instance.address} -u ${var.db_admin_username} -p${var.db_admin_password} computer_store < /tmp/aws-stacks-config-db.sql",
      ### Uninstall MySQL CLI
      "sudo yum -y remove mysql",
    ]
  }

  depends_on = [aws_db_instance.aws-stacks-rds-db-instance, local_file.aws-stacks-file-sql]
}

# Configure EC2 instances

resource "local_file" "aws-stacks-file-php" {
  filename = "${path.module}/index.php"
  content  = <<EOF
<!DOCTYPE html>
<html>
<head>
<title>Compute + Database</title>
</head>
<body>
<?php
//Connect to Database
$mysqli = new mysqli("${aws_db_instance.aws-stacks-rds-db-instance.address}", "${var.db_reader_username}", "${var.db_reader_password}", "${aws_db_instance.aws-stacks-rds-db-instance.db_name}", ${aws_db_instance.aws-stacks-rds-db-instance.port});
if ($mysqli -> connect_errno) {
  echo "<h2>Failed to connect to Database: " . $mysqli -> connect_error . "</h2>";
  exit();
} else {
  echo "<h2>Connected on Database " . $mysqli -> host_info . "</h2>";
}

//Most Purchased products
echo nl2br("\n");
echo "<h3>List of most purchased products:</h3>";
echo "<table border='1' style='width:30%'>";
echo "<tr><th>Name</th><th>Purchased</th></tr>";
$sql = "SELECT products.name, COUNT(*) AS purchased FROM products, orders WHERE products.id=orders.product_id GROUP BY products.name";
$result = $mysqli -> query($sql);
if ($result -> num_rows > 0) {
  while ($row = $result -> fetch_assoc()) {
    echo "<tr><td><center>" . $row["name"] . "</center></td><td><center>" . $row["purchased"] . "</center></td></tr>";
  }
}
echo "</table>";

//Total sales revenues
echo nl2br("\n");
$sql = "SELECT SUM(orders.cost) AS total FROM orders;";
$result = $mysqli -> query($sql);
$row = $result -> fetch_assoc();
$sum = $row['total'];
echo "<h3>Total Sales Revenues: " . $sum . "</h3>";
?>
</body>
</html>
EOF
}

resource "null_resource" "aws-stacks-configure-instance" {
  count = length(data.aws_instances.aws-stacks-ec2-instances.public_ips)

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(data.local_file.aws-stacks-file-key.filename)
    host        = data.aws_instances.aws-stacks-ec2-instances.public_ips[count.index]
  }

  provisioner "file" {
    source      = local_file.aws-stacks-file-php.filename
    destination = "/tmp/index.php"
  }

  provisioner "remote-exec" {
    inline = [
      ### Install PHP for httpd
      "sudo yum -y update",
      "sudo yum -y remove php*",
      "sudo amazon-linux-extras disable php7.4",
      "sudo amazon-linux-extras enable php7.2",
      "sudo yum clean metadata",
      "sudo yum -y install php php-{pear,cgi,common,curl,mbstring,gd,mysqlnd,gettext,bcmath,json,xml,fpm,intl,zip,imap}",
      "sudo systemctl restart httpd",
      ### Deploy new Website
      "sudo cp /tmp/index.php /var/www/html/index.php",
      "sudo sed -i  \"4i<h1>Instance $(hostname -f)</h1>\" /var/www/html/index.php",
      "sudo rm /var/www/html/index.html",
    ]
  }

  depends_on = [null_resource.aws-stacks-configure-database, local_file.aws-stacks-file-php]
}
