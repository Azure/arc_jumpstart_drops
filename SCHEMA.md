# Drop Schema
This document provides guidance on the fields and options that every user should complete when contributing a Drop. The information in this JSON file is used by the Jumpstart Drops platform to create the appropriate card on the page and display relevant content to the user. Additionally, other fields will be utilized to improve the filtering and sorting of the Drops.

As part of the review process, the Jumpstart team will thoroughly examine each of these fields to ensure the contribution meets our high quality standards. Additionally, an automated pipeline will run when the pull request is created to verify that all required fields are completed and adhere to the field rules.

| Parameter | Description | Required | Options | 
| --------- | ----------- | -------- | ------- | 
| Title | A short, descriptive title that reflects the artifact and user experience provided by the Drop | Yes | Maximum 100 characters |
| Summary | A brief, one or two sentence description of the Drop and its purpose. This will be displayed as the Drop Card description. | Yes | Maximum 250 characters |
| Description | A more detailed description of the Drop. This will be displayed in the right bar when a user clicks on the Drop Card. | Yes | Maximum 1000 characters | 
| Cover | A link to an image or video thumbnail that will be displayed as the Drop Card's display image. | No | |
| Authors | A list of all authors and contributors to the Drop. Each author should contain a _Name_ and a _Link_ to the GitHub or Social media account | Yes | | 
| Source | A link to the source code folder in the Arc Jumpstart Drops repository or the public contributor's repository. | Yes | | 
| Type | The type of Drop, based on the Jumpstart Drops list. | Yes | `ui_dashboard_workbook`, `sample_app`, `library_package`, `script_automation`, `template`, `tutorial_guide` | 
| Difficulty | The level of difficulty required to understand and run the Drop, based on the Microsoft Education Center Levels. | Yes | Beginner (L100), Medium (L200), Advanced (L300+) | 
| ProgrammingLanguage | A list of tags for the programming languages used in the Drop. Contributors can add their own language if necessary. | No | PowerShell, .NET/C#, Python, Go, Node, Bash, Bicep, Terraform, Ansible, Helm, Other | 
| Products | A list of products and services used in the Drop. Contributors can add their own if necessary. | No | AKS, Windows IoT, SQL Server, Arc, Arc-enabled service, App Services, VMware |
| LastModified | Not filled by the user. Used to track the last modification of the Drops source code | No | | 
| CreatedDate | Not filled by the user. Used to track when the Drop was created | No | |
| Topics | Not filled by user, but gathered automatically leveraging the GitHub repository topics | No | |

If you believe that any fields are missing or that your Drop content doesn't fit into the JSON schema described above, please create an [Issue](./Issues) and we will do our best to address your concerns.

## Drop Schema Example 
This JSON file provides an example of how a Drop schema file should be structured for a valid contribution.

```json
{
  "Title": "Azure Arc Management & Monitor Workbook",
  "Summary": "This Drop provides a single view for monitoring and reporting on Arc resources using an Azure Monitor workbook offering consistency in managing different environments.",
  "Description": "This Jumpstart Drop provides an Azure Monitor workbook that is intended to provide a single pane of glass for monitoring and reporting on Arc resources. Using Azure's management and operations tools in hybrid, multi-cloud and edge deployments provides the consistency needed to manage each environment through a common set of governance and operations management practices. The Azure Monitor workbook acts as a flexible canvas for data analysis and visualization in the Azure portal, gathering information from several data sources and combining them into an integrated interactive experience.",
  "Cover": "https://github.com/Azure/arc_jumpstart_drops/blob/main/workbooks/arc_management_full/images/cover.jpg",
  "Authors": [
    {
      "Name": "Jane Doe",
      "Link": "https://www.linkedin.com/in/janedoe"
    },
    {
      "Name": "John Smith",
      "Link": "https://github.com/johnsmith"
    }
  ],
  "Source": "https://github.com/Azure/arc_jumpstart_drops/tree/main/workbooks/arc_management_full",
  "Type": "script_automation",
  "Difficulty": "Medium",
  "ProgrammingLanguage": [
    "PowerShell",
    "JSON"
  ],
  "Products": [
    "Azure Monitor",
    "Arc"
  ],
  "LastModified": "2025-02-07T18:25:43.511Z",
  "CreatedDate": "2025-02-01T10:30:16.201Z",
  "Topics": []
}
```
