# Drop Schema
This document provides guidance on the fields and options that every user should complete when contributing a Drop. The information in this JSON file is used by the Jumpstart Drops platform to create the appropriate card on the page and display relevant content to the user. Additionally, other fields will be utilized to improve filtering and sorting of the Drops.

As part of the review process, the Jumpstart team will thoroughly examine each of these fields to ensure the contribution meets our high quality standards. Additionally, an automated pipeline will run when the pull request is created to verify that all required fields are completed and adhere to the field rules.

| Parameter | Description | Required | Options | 
| --------- | ----------- | -------- | ------- | 
| Title | A short, descriptive title that reflects the artifact and user experience provided by the Drop | Yes | |
| Summary | A brief, 1-2 sentence description of the Drop and its purpose. This will be displayed as the Drop Card description. | Yes | Maximum 250 characters |
| Description | A more detailed description of the Drop. This will be displayed in the right bar when a user clicks on the Drop Card. | Yes | Maximum 1000 characters | 
| Cover | A link to an image or video thumbnail that will be displayed as the Drop Card's display image. | No | |
| Authors | A list of all authors and contributors to the Drop. | Yes | | 
| Source | A link to the source code folder in the Arc Jumpstart Drops repository or the public contributor's repository. | Yes | | 
| Type | The type of Drop, based on the Jumpstart Drops list. | Yes | UI/Dashboard, Sample App, Library/Package, Script/Automation, Template, Tutorial/Guide | 
| Difficulty | The level of difficulty required to understand and run the Drop, based on the Microsoft Education Center Levels. | Yes | Beginner (L100), Medium (L200), Advanced (L300+) | 
| Programming Language | A list of tags for the programming languages used in the Drop. Contributors can add their own language if necessary. | No | PowerShell, .NET/C#, Python, Go, Node, Bash, Bicep, Terraform, Ansible, Helm, Other | 
| Products | A list of products and services used in the Drop. Contributors can add their own if necessary. | No | AKS, Windows IoT, SQL Server, Arc, Arc-enabled service, App Services, VMware |
| Last Modified | Not filled by the user. Used to track the last modification of the Drops source code | No | | 
| Created Date | Not filled by the user. Used to track when the Drop was created | No | |
| Topics | Not filled by user, but gathered automatically leveraging the GitHub repository topics | No | |

If you believe that any fields are missing or that your Drop content does not fit into the JSON schema described above, please create an [Issue](./Issues) and we will do our best to address your concerns.
