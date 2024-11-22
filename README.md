# ZED for Windows

Every day, at 03:00 UTC, a new version of Zed will be compiled directly from the official repository. The compilation is performed through GitHub Actions and the configuration file is located within the repository.

To manually initiate a build, please execute the following commands

    git tag -a daily-release-1 -m "daily-release-1"
    git push origin daily-release-1

Or manually execute GitHub Action **Daily release**

[Link to github Zed project](https://github.com/zed-industries/zed)
