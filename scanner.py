import boto3, os
client = boto3.client('ec2', region_name=os.environ.get('AWS_REGION', 'eu-central-1'))

def eip_chk():
  orphans = []
  filters = [
      {'Name': 'domain', 'Values': ['vpc']}
  ]
  response = client.describe_addresses(Filters=filters)
  for addr in response['Addresses']:
          if addr.get('AssociationId') is None:
            orphans.append(f"  AllocationID: {addr['AllocationId']}  PublicIp: {addr['PublicIp']}")
  if orphans:
    print("Orphaned Elastic IPs:")
    for o in orphans:
        print(o)
  else:
    print("No unused Elastic IPs found.")



def sg_chk():

  orphans = []
  enis = client.describe_network_interfaces()
  used_group_ids = set()
  for eni in enis['NetworkInterfaces']:
      for group in eni['Groups']:          # find the key
          used_group_ids.add(group['GroupId'])   # find the key
  response = client.describe_security_groups()
  referenced = set()
  for sg in response['SecurityGroups']:
      for rule in sg['IpPermissions'] + sg['IpPermissionsEgress']:
          for pair in rule['UserIdGroupPairs']:
              referenced.add(pair['GroupId'])
  for sg in response['SecurityGroups']:
      if (sg['GroupId'] not in used_group_ids
              and sg['GroupId'] not in referenced
              and sg['GroupName'] != 'default'):
              orphans.append(f"  Group ID: {sg['GroupId']}  GroupName: {sg['GroupName']}")
  if orphans:
    print("Orphaned SecurityGroups:")
    for o in orphans:
        print(o)
  else:
    print("No unused SecurityGroups found.")

          
def ebs_chk():
  orphans = []
  filters = [{'Name': 'status', 'Values': ['available']}]
  response = client.describe_volumes(Filters=filters)
  for ebs in response['Volumes']:
      orphans.append(f"  Volume ID: {ebs['VolumeId']}  size: {ebs['Size']}GiB  created: {ebs['CreateTime'].strftime('%Y-%m-%d - %H:%M')}")
  if orphans:
    print("Orphaned volumes:")
    for o in orphans:
        print(o)
  else:
    print("No unused volumes found.")


def ec2_chk():
  orphans = []
  filters = [{'Name': 'instance-state-name', 'Values': ['running']}]
  response = client.describe_instances(Filters=filters)
  
  for res in response['Reservations']:
    for ins in res['Instances']:
      orphans.append(f" InstanceId: {ins['InstanceId']} InstanceType: {ins['InstanceType']} LaunchTime: {ins['LaunchTime'].strftime('%Y-%m-%d - %H:%M')}")
  if orphans:
    print("Running EC2s:")
    for o in orphans:
        print(o)
  else:
    print("No running instances found.")




if __name__ == "__main__":
    eip_chk()
    sg_chk()
    ebs_chk()
    ec2_chk()
