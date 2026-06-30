<div align="center"><i>Wally's Little Brother</i></div>

<img src="github/images/LoomBanner.png" alt="" width="100%">

<h1 align="center">Loom, native <a href="https://github.com/upliftgames/wally">Wally</a> package manager for Roblox Studio</h1>

<div align="center">

[![Static Badge](https://img.shields.io/badge/Plugin-white?logo=roblox&label=Marketplace&labelColor=%23363636)](https://create.roblox.com/store/asset/135233720563600/Loom-Import-Wally-Packages)
[![Static Badge](https://img.shields.io/badge/Devforum-00A2FF?logo=robloxstudio&labelColor=%23363636)](https://devforum.roblox.com/t/loom-import-wally-packages-natively-inside-roblox-studio/4711006)

</div>


Loom is a native package manager for Roblox Studio that imports and manages Wally packages directly inside the editor.
Loom is a Roblox Plugin which was created for those unfamiliar with [Rojo](https://rojo.space/), with its simple injection of packages which follow rojo's code structure (```.client.luau```, ```.server.luau```, etc..).

___
<details>
<summary>  <h2>About Wally & Loom</h2> </summary>

 
## About Wally

Wally is a package manager built specifically for the Roblox ecosystem, similar to npm for JavaScript or Cargo for Rust. It allows developers to easily discover, install, and manage reusable code libraries, known as packages, from a centralized registry.

Instead of manually downloading and updating dependencies, Wally handles package installation and version management automatically. This ensures everyone on a team uses the same package versions, reducing compatibility issues and making collaboration much easier. Wally is especially useful alongside Rojo, which enables file system based Roblox development and has become a standard tool for modern Roblox workflows.

## About Loom

Loom brings the power of Wally directly into Roblox Studio, with no command line tools or external setup required.

Loom is a Roblox plugin that makes package management simple for developers who prefer working entirely inside Studio. It provides an easy way to browse, install, and manage Wally packages through a visual interface. Loom also understands Rojo's project structure, supporting file types such as ```.client.luau```, ```.server.luau```, and other context-specific scripts automatically.

This allows developers to use modular code and package management without changing their workflow or learning additional tools. Loom helps bridge the gap between traditional Roblox Studio development and modern software engineering practices, making it easier for both individuals and teams to build organized, scalable projects.

</details>

____
<details>
 
<summary><h2>Plugin Usage</h2></summary>
Before using the plugin, please enable HttpService through your Command Bar in studio, Otherwise Loom will not be able to access HttpService.

<div align="center">
 
<img width="636" height="233" alt="" src="https://github.com/user-attachments/assets/e72e4b8a-aaf5-442b-b823-e3d4405349d2" />

</div>

____

# 1) Retrieving your Wally package

<div align="center">
 
 <img width="75%" alt="" src="https://github.com/user-attachments/assets/31e0e183-a031-4c3d-91bb-47d674169898" />
 
</div>

# 2) Downloading

## Importing locally

<div align="center">

<img width="60%" alt="" src="https://github.com/user-attachments/assets/1f48c125-9a20-40b7-8357-f2658cfdce14" />

</div>

## Importing through "Directory Link"

<div align="center">
 
<img width="45%" alt="" src="https://github.com/user-attachments/assets/50669ba2-7206-436c-ab47-d56799085673" />

</div>

1. In the InputBox, either paste the dependency/package's (```roact = "roblox/roact@1.4.4"```) or simply just type ```roblox/roact```.
2. Click **Get Versions** to load all available versions of the package and to check its authenticity.
3. Choose your preffered version and you'll be able to add the package to the import queue - dependencies are automatically added too

- **Include Dependencies**, is wether or not the current package should install its dependencies too.
- The second **InputBox** is the name of what the "director" Module is going to be called (```author/name```).

### Beginning to Install

<div align="center">
 
<img width="45%" alt="" src="https://github.com/user-attachments/assets/3f0e31a4-c939-4dd9-9335-18662cc6ea11" />

</div>

Once you click the **Add to queue** button, the active package is now ready to be installed. You can continue to add more packages if needed.

Otherwise, you can now click **Install All** and Loom will start processing the creation your package...

<div align="center">
 
<img width="45%" alt="" src="https://github.com/user-attachments/assets/6114e6b9-5dcf-4f78-9069-2f81dd44d475" />

</div>

If needed, you can open the dropdown to edit the **Include Dependencies** checkbox and the package **Name**. Also you can just remove it from the queue.

### And there you go! You've successfully imported a Wally package into roblox.

<div align="center">

<img width="50%" alt="" src="https://github.com/user-attachments/assets/0dcd4b97-f419-40e5-986d-3e7172f58d94" />

</div>

# 3) Additional Information

<div align="center">

<img width="35%" alt="" src="https://github.com/user-attachments/assets/41a76535-09e9-45a0-81fc-51e00b1ccec5" />
<img width="35%" alt="" src="https://github.com/user-attachments/assets/327caf2e-9bee-4d66-9af5-36f3ecc3b216" />

</div>

In side the settings tab, you can change the way Loom behaves.

* **By Enabling Developer/Experimental Mode**, a **Reload Plugin** button will appear. This will restart the plugin completly, its best use case is for when the Version Control fails to retrieve Loom's versions.
* **By Enabling Developer Mode**: a **Logger** will be visible in the Home tab, for debugging and troubleshooting | **Unrestricts certains features and systems**.
* **By Enabling Experimental Mode**: **Version Control** will appear, this is where you can refer Loom to different versions.
* **Resetting to defaults** just reverts the settings you've changed to thier original values.

- Please remember that Loom's unpacking process isnt the best and can very unpredicatable, please [Post Issues](https://github.com/J4KEWasNotHere/Loom/issues) to the GitHub to fix these issues for future versions or changes to the latest version if needed.

</details>

____

# Acknowledgements
I want to give thanks to the users resources or softwares toward the making of **Loom**

**Graphical Design** ( [JakeyRoundHead](https://github.com/J4KEWasNotHere) )

- All visuals and graphics were designed in
 [<img src="https://cdn.simpleicons.org/photopea/000/18A497" width="15" /> Photopea](https://www.photopea.com/)
- Font, [Domus-Extra Bold by _no-one_](https://fonnts.com/font_weights/domus_extrabold-otf/) on [**fonnts.com**](https://fonnts.com/)
- Icons, [<img src="https://cdn.simpleicons.org/gitlab/000/FC6D26" width="15" /> Lucide (For Roblox; plugin) by KoteraHQ/@7kayoh](https://gitlab.com/koterahq/luciderblx/plugin) and [<img src="https://cdn.simpleicons.org/robloxstudio/000/00A2FF" width="15" /> Material Icons (plugin) @qwreey_moe](https://devforum.roblox.com/t/plugin-material-icons-1400/906640)


**Backend** ( [JakeyRoundHead](https://github.com/J4KEWasNotHere) )

- Plugin Framework is a modified reposity of [<img src="https://cdn.simpleicons.org/github/000/fff" width="15" /> **PluginEssentials** by mvyasu](https://github.com/mvyasu/PluginEssentials) accompanied by [**Fusion 0.2** by elttob](https://elttob.uk/Fusion/0.2/)
- Decompression of (.zip) files, [<img src="https://cdn.simpleicons.org/codeberg/000/2185D0" width="15" /> **ZZLib** by zerkman](https://codeberg.org/zerkman/zzlib)

# <img src="github/images/LoomIcon.png" width="46" /> License & Holder Agreement
Loom is available under the (Inherited) <kbd>MPL-2.0 License <img src="https://cdn.simpleicons.org/mozilla/000/fff" width="15" /></kbd>. Terms and conditions are available in [LICENSE.txt](https://github.com/J4KEWasNotHere/Loom/blob/main/LICENSE.txt) or at the [Official Website](https://www.mozilla.org/en-GB/MPL/2.0).

With respect of </b>[@UpliftGames](https://github.com/UpliftGames)</b>, and <kbd>[<img src="https://cdn.simpleicons.org/mozilla/000/4493f8" width="15" /> Wally's License (MPL-2.0 License)](https://github.com/UpliftGames/wally/blob/main/LICENSE.txt)</kbd>. I hereby consent to any actions or modifications, including deletion, that they may make toward <kbd>[<img src="github/images/LoomIcon.png" width="16" />  J4KEWasNotHere/**Loom**](https://github.com/J4KEWasNotHere/Loom)</kbd>.

<div align="center"><a href="https://www.roblox.com/communities/34077341/Kalaran#!/about"><img src="github/images/KalaranBanner.png" alt="" width="50%"></a></div>
