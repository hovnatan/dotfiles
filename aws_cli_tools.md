curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install # install aws-cli
aws configure # configure
aws ec2 start-instances --instance-ids i-myid
aws ec2 describe-instances --filters Name=instance-id,Values=i-myid # to find out PublicDnsName
aws ec2-instance-connect send-ssh-public-key --instance-id i-myid --instance-os-user=ubuntu --ssh-public-key=file:///home/hovnatan/.ssh/id_ed25519.pub # to send public-key
ssh ubuntu@aaaast-2.compute.amazonaws.com # ssh into it
aws ec2-instance-connect ssh --instance-id i-myid --os-user=ubuntu # or use this
# instead of 3 steps above
aws ec2 stop-instances --instance-ids i-myid
