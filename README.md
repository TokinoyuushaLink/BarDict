# BarDict
macOS菜单栏mdx/mdd查词app

<img width="394" height="437" alt="截屏2026-05-26 下午8 25 52" src="https://github.com/user-attachments/assets/1f189005-a8ee-4a2d-8919-2b9f2ce6f2ca" />
<img width="386" height="574" alt="截屏2026-05-26 下午8 26 10" src="https://github.com/user-attachments/assets/97ec3a06-d428-4473-b456-74855b3c691c" />
<img width="224" height="246" alt="截屏2026-05-26 下午8 26 18" src="https://github.com/user-attachments/assets/65110182-edee-4d68-b80f-193c0b59f749" />

## 特性：
- 简洁友好，使用WKWebView进行渲染
- 动态高度缩放，带有些许动画
- 支持现有MDict2.x，1.x,lzo压缩格式的mdx
- 支持全局快捷键打开，目前有shift+space和option+space
- 允许多词典命中，多词典切换


## 操作：
- 点击菜单栏图标/全局快捷键打开菜单栏app
- 输入单词
- tab/shift+tab 或 ↑ / ↓ 键进行候选切换
- Enter输入
- Esc从详细视图切回/关闭菜单窗口

## 编译：
1. 首先，你需要Command-Line-Tool，uv
2. Bash
   ```
   chmod +x build.sh
   ./build.sh
   ```
## 构建SQLite数据库：
1. 在代码栏里找到mdx2db.py
2. Bash
   ```
   uv run mdx2db.py 你的词典文件.mdx
   ```
3. 构建的数据库会自动放入`~/Library/Application Support/BarDict/`中，如果路径不存在请手动创建


---

## Features：
- Clean and friendly UI, rendered with WKWebView  
- Dynamic height scaling with subtle animation  
- Supports existing MDict 2.x, 1.x, and lzo-compressed MDX formats  
- Global hotkey support (currently Shift+Space and Option+Space)  
- Supports multiple dictionary matches and switching between them  

## Usage:
- Click the menu bar icon / use global hotkey to open the menu bar app  
- Enter a word  
- Use Tab / Shift+Tab or ↑ / ↓ keys to cycle through candidates  
- Press Enter to confirm  
- Press Esc to return from detailed view / close the menu window  

---

## Build Instructions:
1. First, install Command Line Tools and `uv`  
2. Run:  
   ```  
   chmod +x build.sh  
   ./build.sh  
   ```  

## Building SQLite Database:
1. Locate `mdx2db.py` in the code  
2. Run:  
   ```  
   uv run mdx2db.py YourOwnMdxFile.mdx  
   ```  
3. The generated database will be automatically placed in `~/Library/Application Support/BarDict/` — create the path manually if it doesn't exist
