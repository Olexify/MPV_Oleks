# mpv configuration - this is my modification, but originally config is done by [Tuilakhanh](https://github.com/tuilakhanh/mpv-conf) *I'll aks him and if he opposes I'll delete my work or proper;y fork it later, I'm new to git and didn't plan to publish it xD*
**This mpv configuration is done on mpv-git. Make sure you are using the latest version of mpv-git if you want to use this configuration.**
![thumb](https://github.com/tuilakhanh/mpv-conf/assets/17153084/908b4514-d85f-4c99-b9c1-28245795ea94)
## 📦 Installation

Download mpv from https://mpv.io  
Extract it anywhere  
Copy the `portable_config` folder into the mpv folder  

### Final structure:
```
mpv/
├── mpv.exe
└── portable_config/
```

Run `mpv.exe` (optionally set it as default video app)

![preview](https://github.com/user-attachments/assets/e0dbecae-1f59-4032-9a66-33231feeb16a)

---

## My version of config

- A bit stripped down: removed Ziggy online subtitles (flagged as malware, archived for safety). Path: `portable_config/scripts/uosc/bin`
- Custom delete behavior:
  - Delete → move to trash
  - Shift + Delete → permanent delete (with confirmation)
- Sorting + navigation improvements:
  - Infinite video cycling
  - Images do not auto-cycle
- Work in progress improvements

---

## Tiny comfortable tweaks

- Pause on mouse click  
- Left/Right arrows: seek ±4 seconds  
- Up/Down arrows: next video/photo  



## Scripts and Shaders Credits

- [mpv-player/autocrop](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autocrop.lua)
- [ObserverOfTime/clipshot](https://github.com/ObserverOfTime/mpv-scripts/blob/master/clipshot.lua)
- [po5/evafast](https://github.com/po5/evafast)
- [po5/memo](https://github.com/po5/memo)
- [voz.vn/protocol_hook](https://github.com/FirefoxUniverse/FirefoxTweaksVN/tree/main/mpv)
- [natural-harmonia-gropius/quality-menu](https://github.com/natural-harmonia-gropius/mpv-quality-menu)
- [4e6/mpv-reload](https://github.com/4e6/mpv-reload)
- [snylonue/slicing_copy](https://github.com/snylonue/mpv_slicing_copy) (Modified)
- [jouni/mpv_sponsorblock_minimal](https://codeberg.org/jouni/mpv_sponsorblock_minimal)
- [Sagnac/streamsave](https://github.com/Sagnac/streamsave)
- [po5/thumbfast](https://github.com/po5/thumbfast)
- [tomasklaen/uosc](https://github.com/tomasklaen/uosc)
- [serenae-fansubs/webm](https://github.com/serenae-fansubs/mpv-webm)
- [Idlusen/mpv-ytsub](https://github.com/Idlusen/mpv-ytsub)

---

- [bjin/mpv-prescalers](https://github.com/bjin/mpv-prescalers/tree/master/gather)
    - RAVU
    - NNEDI
- [igv/gist](https://gist.github.com/igv)
    - KrigBilateral.glsl
- [Artoriuz/glsl-chroma-from-luma-prediction](https://github.com/Artoriuz/glsl-chroma-from-luma-prediction)
    - CfL_Prediction.glsl
- [Artoriuz/ArtCNN](https://github.com/Artoriuz/ArtCNN)
    - ArtCNN (Compute Version)
- [an3223/shaders](https://github.com/AN3223/dotfiles/tree/master/.config/mpv/shaders)
    - nlmeans.glsl
    - hdeband.glsl
- [haasn/libplacebo.org](https://libplacebo.org/custom-shaders/#full-example)
    - filmgrain.glsl
