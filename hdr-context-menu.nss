// HDR: build one live item from the Windows display helper's current state.
remove(type="desktop" mode="none" find="Toggle HDR|Enable HDR|Disable HDR")
item(type="desktop" mode="none" pos=indexof('Display settings', 0, pos.bottom)
    where=io.file.exists('@@INSTALL@@\MenuLabel.txt')
    title=io.file.read('@@INSTALL@@\MenuLabel.txt')
    image='@@INSTALL@@\'+io.file.read('@@INSTALL@@\MenuIcon.txt')
    vis=(io.file.read('@@INSTALL@@\MenuLabel.txt') == 'HDR: Unavailable' ? vis.static : vis.normal)
    cmd='@@WINDOWS@@\System32\wscript.exe'
    args='//NoLogo "@@INSTALL@@\Toggle-HdrSdr.vbs" '+(io.file.read('@@INSTALL@@\MenuLabel.txt') == 'Disable HDR' ? 'Off' : 'On'))
