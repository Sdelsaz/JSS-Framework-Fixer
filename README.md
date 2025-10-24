![alt text](https://github.com/Sdelsaz/JSS-Framework-Fixer/blob/main/images/icon1.png?raw=true)

# JSS Framework Fixer

A script to help re-deploy the Jamf Pro Framework to a Smart Computer Group. An existing Smart Computer Group can be can used or a new one can be created.  The New Smart Computer Group will use the number of days since the last inventory update as criteria. A prompt will ask for the number of days to use for the criteria. 

This script leverages the Jamf Pro API and is to be run on an administrator's mac, it is not meant to be deployed using Jamf Pro.  The script must be run as root. Prompts are used to gather the server details credentials for the API calls.

Logs are written to /var/log/JSS-Framework-Fixer.log

This script uses Bart Reardon's swiftDialog for user dialogs:

https://github.com/bartreardon/swiftDialog

![alt text](https://github.com/Sdelsaz/JSS-Framework-Fixer/blob/main/images/1.png?raw=true)

![alt text](https://github.com/Sdelsaz/JSS-Framework-Fixer/blob/main/images/3.png?raw=true)

![alt text](https://github.com/Sdelsaz/JSS-Framework-Fixer/blob/main/images/5.png?raw=true)

![alt text](https://github.com/Sdelsaz/JSS-Framework-Fixer/blob/main/images/6.png?raw=true)


## Requirements:

- Jamf Pro 10.36 or later
- local administrtor privileges to run the script as root/use sudo
- A valid MDM profile and network connection on the target computer
- The following privileges in Jamf Pro:

Jamf Pro Server Objects:
Smart Computer Groups: Create, Read

Jamf Pro Server Settings:
Check-in: Read

Jamf Pro Server Actions:
Send Computer Remote Command to Install Package
