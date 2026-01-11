# QuickNote

QuickNote is a simple markdown note-taking app for MacOS, written in Swift. When the app is launched, simply press `ctrl + option + cmd + o` and start writing. 

## Disclaimer 

This project is mostly a way for me to experiment with ‘vibe-coding’. *I am not a developer, and I don’t know Swift*. All the code was written by Claude Code. It works fine for me, but it may contain a variety of bugs and potentially make unwanted modifications to your files. 

## To build the app

Run
```
# Build release
cd /Users/raphaelhuleux/Desktop/1_projects/QuickNote
swift build -c release
rm -rf QuickNote.app
mkdir -p QuickNote.app/Contents/MacOS QuickNote.app/Contents/Resources
cp .build/release/QuickNote QuickNote.app/Contents/MacOS/
cp QuickNote/Info.plist QuickNote.app/Contents/
cp QuickNote/AppIcon.icns QuickNote.app/Contents/Resources/
```