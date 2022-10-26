# **Introduction**
This repository contains information about AppCode infrastructure state described as a code, and some additional scripts/utils.

- - - -

# **Repo overview**


[![arch] (https://lucid.app/publicSegments/view/82deb2ac-c30c-459a-9623-8a87bbb8fa08/image.png)]

## _scripts_
`scripts` folder stores shell scripts:  



## _CloudFormation_
`CloudFormation` folder contains CF template, parameters, metadata and deployment script:  
- [DynamoDB](./DynamoDB) folder - stores DDB Items for Configuration table
- [Parameters](./Parameters) folder - stores environment-specific input params for CF template
- [template.yaml](./template.yaml) - CF template which does spin up APP environment
- [CHANGELOG.md](./CHANGELOG.md) - file is used to list changes made template.yaml
- [cloudformation.sh](./cloudformation.sh) - script deploys/updates CF stack (environment)
