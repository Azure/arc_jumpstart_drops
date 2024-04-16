## Contribution Process

This project welcomes contributions and suggestions through GitHub, following the Azure Arc Jumpstart [Contribution Guidelines](https://arcjumpstart.com/contribution_guidelines). 

| ℹ️ Information                           | 
|------------------------------------------|
| All Drops must be submitted under an MIT License. For more information, see [Licensing](./LICENSE).  |

### Overview

Our goal is to create a simplified contribution process for our users that guarantees high quality standards fo all submissions. Contributors can create submissions using GitHub directly, or leverage Jumpstart Drops page [Submit Drop](./) form to expedite the process. 

The contribution process consists of the following steps:

![Contribution process](./img/contributing.png)

1. **Define source code hosting** : There are two accepted alternatives to host the source code:

    - **Include Code in PR:** Include the code in the PR and host it as part of the [Arc Jumpstart Drops repository](https://github.com/Azure/arc_jumpstart_drops).
    - **Reference Author's Repository:** Keep the code in the author's repository and provide a reference/URL in the Drop definition file (check [Drops schema](./SCHEMA.md)). Ensure that the repository is publicly available.

1. **Drops artifacts creation**: Develop and validate the source code of the Drop and the JSON definition file. Ensure to test end to end, and provide clear documentation. The required artifacts include:

    - **Source Code**: Include the script/app/dashboard you've created, along with any necessary documentation (README, images, videos, etc.). Ensure these files follow the correct structure defined in the [folder structure](#folder-structure) section. 

    - **Drop Definition**: Provide a JSON file with all the required fields as described in the [Drops Schema](./SCHEMA.md) definition. This file will be used by the Arc Jumpstart Drops page to create a Drop card with all the necessary information, as well as apply the correct filtering mechanisms.  

        **Important:** The Drop definition JSON file should be placed under the [drops](./drops/) folder, and the name should be unique, descriptive and using snake_case.

1. **Create Pull Request to Canary**: Submit your pull request (PR) to the Canary branch of [Arc Jumpstart Drops](https://github.com/Azure/arc_jumpstart_drops).

1. **GitHub Checks**: GitHub checks will run to ensure:

    - Drop definition and folder structure.
    - MIT licensing check
    - CodeQL for vulnerabilities.
    - Vale.sh Linter for documentation grammar and styling.

1. **Manual review from Jumpstart Core maintainers**: Automatic reviewers will be added. The PR can only be merged if all GitHub checks pass and at least 2 reviewers approved the submission.

1. **Merge to Canary**: If everything is correct, the PR will be merged to the **canary** branch, and the new Drop will be part of the approved Drops curated list. 

1. **Validation with Preview Site**: Validate the changes using the [Preview Azure Arc Jumpstart site](https://preview.arcjumpstart.com/arc_jumpstart_drops).

1. **Merge to Main**: Finally, once the **Canary** branch is merged to **Main** and publish to Production, the Drop will be available as part of [Azure Arc Jumpstart Drops](https://arcjumpstart.com/arc_jumpstart_drops).

### Drop Index


### Folder structure

When submitting the Drop source code as part of the Pull Request into the Arc Jumpstart Drops repository, we encourage contributors to adhere to the following folder structure.

<img src="./img/folder_structure.png" alt="Folder structure" width="500">

1. A root folder with the name of the Drop, using **snake_case** (for example, azure_arc_management_and_monitor_workbook)

1. Inside the root folder, a file name **_index.md** equivalent to a README file for the Drop. This file provides a brief introduction and overview of the Drop, its objectives, prerequisites, deployment steps, and any additional resources or references.

1. Inside the root folder, a new folder named **artifacts** that contains all the files and scripts that are needed to deploy the Drop.

1. Optionally, inside the artifacts folder, a new folder named **media** that contains any screenshots or architecture diagrams to showcase the Drop.