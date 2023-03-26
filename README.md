# iplist_checker
## To download and detect the changes of IPv4 CIDR pubished by some service provider


- The IP list from Cloudflare(China), updates at least every 30 days
- The runbook runs every day, to compare the list with yesterday's
- And sends out notification emails once change is detected So the NSG/Firewall which allows the IP list, will need to be updated accordingly

## Pre-created resources: 
- Storage account and container
- Automation Account credentials for SMTP authentication
- System identity for automation account to have RW access of the storage account 
