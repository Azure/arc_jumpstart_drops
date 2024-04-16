# FAQs

### What is Arc Jumpstart Drops?
Arc Jumpstart Drops serves as a curated collection of scripts, tools, and other resources that can help developers/IT/OT and maintenance professionals streamline their day-to-day operations and smooth their [Adaptive Cloud](https://arcjumpstart.com/adaptive_cloud) journey. 

### Can I contribute a Drop?
Arc Jumpstart Drops is fully open-source and welcomes all contributions that follow the Drops [contribution process](./CONTRIBUTING.md). Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant Arc Jumpstart team the rights to use your contribution. For details, visit [Microsoft CLA](https://cla.opensource.microsoft.com).

### Do I need to host my source code inside the Jumpstart Drops repository?
No, it's not necessary to host your source code in the Drops repository. You have two options for hosting the code, and you can choose the one that suits your use case better:

- **Include the code in the Pull Request (PR)**: You can include the code as part of your PR and host it within the Arc Jumpstart Drops repository.
- **Keep the code in your own repository**: Alternatively, you can keep the code in your own repository and provide a reference/URL to it in the Drop [definition file](./SCHEMA.md).

### Do I need to authenticate to the Jumpstart portal to contribute or use Drops?
No, authentication and logging in to the portal are not required to contribute or use Jumpstart Drops. However, if you are logged in, we are developing features to provide contributors with insights on their contributions and enhance their experience and submission.

### What is the Drop licensing schema?
Jumpstart Drops follows the same [MIT](./LICENSE) licensing as all the other Arc Jumpstart Products. All contributions should also be under an [MIT](./LICENSE) license. 

The MIT license is a permissive open-source software license that allows for the use, modification, and distribution of the licensed software, as long as the original copyright notice and license terms are included in any copies or distributions of the software. 

For more information, see [contribution process](./CONTRIBUTING.md).

### How can I discover a Drop?
To discover a Drop tailored to your needs, leverage the filters and sorting options available on the Arc Jumpstart Drops main page. Start by visiting [Arc Jumpstart Drops](https://arcjumpstart.com/arc_jumpstart_drops) and then use the panel on the right-hand side to filter by criteria such as *Programming* *Language*, *Product*, *Difficulty*, *Industry*, *Topic*, and more. Additionally, you can always use the search bar at the top to search across all Jumpstart content, including Jumpstart Drops.

### How do I use a Drop?
Using Drops is straightforward. Simply download the Drop by clicking the Download button on the Drop's page or by making an API call directly. After downloading, you will have a .zip file containing all the necessary source code to run the Drop. Depending on the Drop, you may need to configure some prerequisites, but all instructions should be included in the **_index.md** file of the Drop.

### How do I submit a Drop?
Submitting a Drop is easy. You can choose to create a pull request directly in the Arc Jumpstart Drops repository or use the [Submit Drop](https://arcjumpstart.com/arc_jumpstart_drops) form for a streamlined process. Refer to the Drops [contribution process](./CONTRIBUTING.md) guide for detailed instructions.

### How is support and maintenance handled for Drops?
Support and maintenance for Drops are managed through GitHub Issues, where bugs and feature requests can be tracked. The project follows the support approach outlined in [Arc Jumpstart Support](https://github.com/Azure/arc_jumpstart_docs/blob/main/SUPPORT.md

**Important**: _Please note that Drops do not come with official support or warranty, but the community is encouraged to provide assistance to the best of their ability._

### What tools are used for code maintenance in this project?
All Drop owners are responsible for the code maintenance of their source code. If you chose to host the Drop source code as part of the Jumpstart Drops repository, we will run some check for code maintenance, like **CodeQL** and **GitHub Dependabot** security alerts. We're actively looking into developing new features to help contributors maintain their source code. If you have suggestions, please create an [Issue](./issues) with your suggested appraoch.