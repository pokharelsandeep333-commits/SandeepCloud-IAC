# Both servers live in the default VPC, in the default subnet for us-east-1c.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "default_c" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "${var.region}c"
  default_for_az    = true
}
