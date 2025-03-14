# apichanges

A tool for easily tracking changes in OpenAPI specification files. It examines a specific file in a repository and uses Git history to determine the list of changes for today, yesterday, or the last 7 days. It leverages [oasdiff](https://github.com/oasdiff/oasdiff) under the hood.

## Install

Simply copy the apichanges.sh script to your environment and run it with the desired parameters.

```bash
curl -fsSL https://raw.githubusercontent.com/serg-the-engineer/apichanges/main/apichanges.sh
```

## Usage

The tool checks for the `oasdiff` installation and downloads binary if needed. No additional dependencies are required. Use it inside your Git repository.

```bash
./apichanges.sh -y path/to/api.yaml
```

This command generates 5 files for your analysis:
- `v1.yaml`: spec from earliest yesterday revision
- `v2.yaml`: spec from latest yesterday revision
- `summary.yaml`: a brief summary of changes
- `breaking.md`: a list of breaking changes (warn and err) in markdown format for easy text viewing
- `changelog.html`: a fully formatted changelog for web viewing

To share resulting changelog without additional actions, execute the following command...

```bash
./apichanges.sh -wuc -p path/to/api.yaml
```
- `-w`: generates a changelog for the last 7 days
- `-p`: an alternative way to specify the API file path
- `-u`: uploads `changelog.html` to temporary file hosting service (0x0.st) and provides shareable link
- `-c`: cleans up all created files after execution

... and Ctrl+V (if pbcopy installed) link into your chat or use in a CI webhook.

## Customizing checkers

`oasdiff` allows you to customize checker levels to suit your needs. `apichanges` supports this feature - simply place `oasdiff-levels.txt` file next to the script and define your rules.

## Gitlab CI Integration

If you use Gitlab, you can automate daily changelog generation using Gitlab Schedules and the scripts in the `gitlab/` folder. In contains example of cloning another repo. Comment out the clone command if the CI is already running in the target repository.

Gitlab Pages is used insted of 0x0.st

This setup includes an opinionated way of using oasdiff formatting options and a notification template, making it ideal for quick starts.

The template for the JSON-formatted webhook message in `sendwebhook.sh` is as follows

```json
{
  "text": "$MESSAGE_TEXT"
}
```