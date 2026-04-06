# Changelog

## [v0.1.1] - 2026-04-06

## Changes in v0.1.1

- ✨ **Feature**: chore: initialize versioning and update changelog for v0.1.0
- ✨ **Feature**: add forum post generator and project configuration
  - Introduced `forum-post-generator.sh` to automate the creation of forum posts for releases, including HTML formatting and download links for artifacts.
  - Added `project-config.sh` for project-specific settings, including project name, GitHub repository, and artifact generation configurations.
  - Created `project-config.sh.example` as a template for users to customize their project settings.
  - Implemented `setversion.sh` to update version numbers across multiple files, ensuring consistency in versioning.
  - Enhanced validation and error handling in configuration and version setting scripts.
- ✨ **Feature**: Refactor device classes and update AirSensor functionality
  - Removed duplicate ChildDimmableLight class definition in Devices.lua.
  - Updated LightController to inherit from DirigeraDevice.
  - Enhanced AirSensor class with a change method to handle reachability and update child properties.
  - Fixed waterSensor mapping to use WaterSensor class instead of NoDevice.
  - Updated Dirigera.lua to improve token handling and device initialization.
  - Added new Devices2.lua file with comprehensive device class definitions.
  - Introduced Dirigera2.lua for improved structure and organization of the Dirigera connectivity code.
- ✨ **Feature**: Refactor Dirigera.lua metadata and update version to 1.01
  - Changed metadata format to use new syntax for UID, save, proxy, and other attributes.
  - Updated the debug variable to reflect new settings.
  - Modified the method of retrieving the TOKEN to use environment variables.
  - Adjusted version number from 1.0 to 1.01.
- ✨ **Feature**: Enhance Dirigera and Dirigera2 configurations and add .gitignore and VSCode settings
  - Updated Dirigera.lua to include web UI support and changed token retrieval method.
  - Modified Dirigera2.lua to adjust development path and added web UI support.
  - Introduced .gitignore to exclude unnecessary files from version control.
  - Added VSCode settings for improved development environment configuration.
- ✨ **Feature**: Add link to IKEA Dirigera forum in release information
- ✨ **Feature**: Update development path and modify token management in Dirigera scripts
- ✨ **Feature**: Implement new feature for enhanced user authentication


*Generated automatically from git commits*

## [v0.1.0] - 2026-04-06

## Changes in v0.1.0

- ✨ **Feature**: add forum post generator and project configuration
  - Introduced `forum-post-generator.sh` to automate the creation of forum posts for releases, including HTML formatting and download links for artifacts.
  - Added `project-config.sh` for project-specific settings, including project name, GitHub repository, and artifact generation configurations.
  - Created `project-config.sh.example` as a template for users to customize their project settings.
  - Implemented `setversion.sh` to update version numbers across multiple files, ensuring consistency in versioning.
  - Enhanced validation and error handling in configuration and version setting scripts.
- ✨ **Feature**: Refactor device classes and update AirSensor functionality
  - Removed duplicate ChildDimmableLight class definition in Devices.lua.
  - Updated LightController to inherit from DirigeraDevice.
  - Enhanced AirSensor class with a change method to handle reachability and update child properties.
  - Fixed waterSensor mapping to use WaterSensor class instead of NoDevice.
  - Updated Dirigera.lua to improve token handling and device initialization.
  - Added new Devices2.lua file with comprehensive device class definitions.
  - Introduced Dirigera2.lua for improved structure and organization of the Dirigera connectivity code.
- ✨ **Feature**: Refactor Dirigera.lua metadata and update version to 1.01
  - Changed metadata format to use new syntax for UID, save, proxy, and other attributes.
  - Updated the debug variable to reflect new settings.
  - Modified the method of retrieving the TOKEN to use environment variables.
  - Adjusted version number from 1.0 to 1.01.
- ✨ **Feature**: Enhance Dirigera and Dirigera2 configurations and add .gitignore and VSCode settings
  - Updated Dirigera.lua to include web UI support and changed token retrieval method.
  - Modified Dirigera2.lua to adjust development path and added web UI support.
  - Introduced .gitignore to exclude unnecessary files from version control.
  - Added VSCode settings for improved development environment configuration.
- ✨ **Feature**: Add link to IKEA Dirigera forum in release information
- ✨ **Feature**: Update development path and modify token management in Dirigera scripts
- ✨ **Feature**: Implement new feature for enhanced user authentication


*Generated automatically from git commits*

