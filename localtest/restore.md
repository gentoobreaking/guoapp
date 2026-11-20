更快的 ADB 直搬法（如果你有電腦連電視）
# 1. 備份舊版私有目錄到電腦
adb backup -f guoapp.ab -noapk com.guoapp.app

# 2. 安裝新版
adb install -r guoapp_new.apk

# 3. 恢復到新包名（需新版已運行過一次建立目錄）
adb restore guoapp.ab
注意：adb restore 會按包名寫入，所以新版必須先跑一次建立 com.videoapp.app 目錄，再 restore。
