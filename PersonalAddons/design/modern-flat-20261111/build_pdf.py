#!/usr/bin/env python3
"""Build the local-only MyForever visual and interaction bible. No game files change."""
from pathlib import Path
import json, html, re
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
from pypdf import PdfReader

ROOT=Path(__file__).resolve().parent
FONT='/Library/Fonts/Microsoft/Microsoft Yahei.ttf'
pdfmetrics.registerFont(TTFont('BibleSans', FONT))
W,H=960,600
C={'bg':'#111214','panel':'#222326','raised':'#303236','hover':'#3A3D42','line':'#4B4F56','ink':'#F5F5F7','muted':'#C0C3C9','quiet':'#969BA5','brand':'#8BBEF3','onbrand':'#132335','primary':'#0A64C5','onprimary':'#FFFFFF','success':'#79D7BE','gold':'#E2C183','warning':'#F2C46D','danger':'#F28B82','info':'#8DBFF2','paper':'#F4F6F7','black':'#17232D','body':'#425462','lightline':'#DCE2E6','white':'#FFFFFF','target':'#FF514F','focus':'#FFD353','difficulty':'#FF7D2F'}
pdf=canvas.Canvas(str(ROOT/'MyForever-Art-Bible.pdf'),pagesize=(W,H),pageCompression=1)
pdf.setTitle('我的无限 · 静石 | 原生工具窗与 HUD 美术圣经 v1.2')
pdf.setAuthor('MyForever · Design proposal')
PAGE=0
BOOK=[]
WARN=[]

def color(key): return HexColor(C.get(key,key))
def rect(x,y,w,h,fill='paper',r=0,stroke=None,sw=1):
    pdf.setFillColor(color(fill)); pdf.setStrokeColor(color(stroke or fill)); pdf.setLineWidth(sw)
    if r: pdf.roundRect(x,H-y-h,w,h,r,stroke=bool(stroke),fill=1)
    else: pdf.rect(x,H-y-h,w,h,stroke=bool(stroke),fill=1)
def surface(x,y,w,h,fill='panel',r=0,alpha=.84,stroke=None,sw=1):
    pdf.saveState()
    # ReportLab Color carries alpha=1, so alpha must be set AFTER the colour.
    pdf.setFillColor(color(fill));pdf.setStrokeColor(color(stroke or fill))
    pdf.setFillAlpha(alpha);pdf.setStrokeAlpha(.55);pdf.setLineWidth(sw)
    if r:pdf.roundRect(x,H-y-h,w,h,r,stroke=bool(stroke),fill=1)
    else:pdf.rect(x,H-y-h,w,h,stroke=bool(stroke),fill=1)
    pdf.restoreState()

def scene(x,y,w,h,light=False):
    """Neutral flat-plane underlay. It is not a WoW screenshot or a blur simulation."""
    rect(x,y,w,h,'#8C8F95' if light else '#53565D',6)
    path=pdf.beginPath()
    path.moveTo(x+2,H-y-h*.70);path.lineTo(x+w*.43,H-y-h*.17)
    path.lineTo(x+w*.70,H-y-2);path.lineTo(x+w-2,H-y-2)
    path.lineTo(x+w-2,H-y-h*.39);path.lineTo(x+w*.55,H-y-h*.65)
    path.lineTo(x+w*.25,H-y-h+2);path.lineTo(x+2,H-y-h+2);path.close()
    pdf.setFillColor(color('#B0B3B8' if light else '#737780'));pdf.drawPath(path,fill=1,stroke=0)
    path=pdf.beginPath()
    path.moveTo(x+w*.45,H-y-h+2);path.lineTo(x+w*.68,H-y-h*.51)
    path.lineTo(x+w-2,H-y-h*.30);path.lineTo(x+w-2,H-y-h+2);path.close()
    pdf.setFillColor(color('#777B83' if light else '#41454D'));pdf.drawPath(path,fill=1,stroke=0)
    pdf.saveState();pdf.setStrokeAlpha(.28)
    line(x+w*.05,y+h*.28,x+w*.81,y+h*.91,'#CAD0D7',.7)
    line(x+w*.14,y+h*.05,x+w*.94,y+h*.67,'#CAD0D7',.7)
    pdf.restoreState()

def line(x,y,x2,y2,c='lightline',sw=1):
    pdf.setStrokeColor(color(c));pdf.setLineWidth(sw);pdf.line(x,H-y,x2,H-y2)
def t(s,x,y,size=11,c='black',maxw=None,align='left'):
    s=str(s)
    if maxw and pdfmetrics.stringWidth(s,'BibleSans',size)>maxw:
        WARN.append((PAGE,s,'width',maxw,pdfmetrics.stringWidth(s,'BibleSans',size)))
    if y>580: WARN.append((PAGE,s,'bottom',y))
    pdf.setFont('BibleSans',size);pdf.setFillColor(color(c))
    fn=pdf.drawRightString if align=='right' else pdf.drawString
    fn(x,H-y-size,s)
def wrap(s,width,size=11):
    lines=[]
    for para in str(s).split('\n'):
        cur=''
        for ch in para:
            if pdfmetrics.stringWidth(cur+ch,'BibleSans',size)>width and cur:
                lines.append(cur);cur=ch
            else:cur+=ch
        lines.append(cur)
    return lines
def p(s,x,y,width,size=11,c='body',leading=None):
    leading=leading or size*1.6
    for row in wrap(s,width,size): t(row,x,y,size,c);y+=leading
    return y

def block(title,body,x,y,width=350):
    t(title,x,y,13,'black');return p(body,x,y+24,width,10.5,'body',17)+19

def bullets(items,x,y,width=350):
    for title,body in items:
        y=block(title,body,x,y,width)
    return y

def page(title,subtitle='',dark=False):
    global PAGE
    PAGE+=1
    rect(0,0,W,H,'bg' if dark else 'paper')
    t('我的无限 · 静石',44,24,11,'muted' if dark else 'body')
    t('UI / UX 美术圣经 · 原生工具窗提案 v1.2',916,24,10,'quiet' if dark else 'body',align='right')
    t(title,44,63,27,'ink' if dark else 'black')
    if subtitle:p(subtitle,44,104,870,11,'muted' if dark else 'body',17)
    line(44,554,916,554,'line' if dark else 'lightline')
    t('2026.11.11  ·  本地设计候选  ·  所有界面数据均为虚构示例',44,566,8.5,'quiet' if dark else 'body')
    t(f'{PAGE:02d} / 19',916,566,9,'quiet' if dark else 'body',align='right')
    BOOK.append({'title':title,'subtitle':subtitle,'content':[]})

def finish(): pdf.showPage()
def note(s):BOOK[-1]['content'].append(s)
def btn(caption,x,y,w=86,primary=False,disabled=False):
    fill='primary' if primary else 'raised'
    if disabled:fill='raised'
    rect(x,y,w,26,fill,4)
    t(caption,x+w/2-pdfmetrics.stringWidth(caption,'BibleSans',10)/2,y+6,10,'quiet' if disabled else ('onprimary' if primary else 'ink'))
def tag(label,x,y,c='brand'):
    t(label,x,y,9,c)
def panel(title,x,y,w,h,subtitle=None,role='tool'):
    scene(x,y,w,h)
    opacity={'tool':.84,'hud':.72,'alert':.80,'popover':.90}[role]
    surface(x,y,w,h,'panel',6,alpha=opacity,stroke='line',sw=.6)
    line(x+1,y+36,x+w-1,y+36,'line',.6)
    t(title,x+14,y+10,13,'ink')
    t('−',x+w-49,y+8,14,'muted');t('×',x+w-25,y+8,14,'muted')
    if subtitle:t(subtitle,x+14,y+45,9,'muted')
def rule(x,y,w):line(x,y,x+w,y,'line',.6)
def row(title,sub,x,y,w=430,selected=False,end=None):
    if selected:surface(x,y,w,42,'hover',3,alpha=.60)
    t(title,x+10,y+6,11,'ink')
    if sub:t(sub,x+10,y+24,8.5,'muted')
    if end:t(end,x+w-10,y+7,10,'muted',align='right')
def progress(x,y,w,ratio,c='brand',height=5):
    rect(x,y,w,height,'raised',2);rect(x,y,w*ratio,height,c,2)
def inputbox(value,x,y,w=240):
    rect(x,y,w,28,'bg',4,stroke='line',sw=.7);t(value,x+10,y+7,10,'ink')

def professions(x,y,w=462,h=352):
    panel('商业技能助手',x,y,w,h)
    t('专业进度',x+14,y+49,10,'muted');t('技能书',x+w-73,y+49,10,'brand')
    row('锻造','当前专业',x+10,y+71,w-20,True,'85 / 150')
    progress(x+24,y+121,w-48,85/150)
    t('建议训练',x+24,y+140,10,'muted')
    rule(x+14,y+218,w-28)
    t('铜质符文腰带',x+26,y+171,12,'ink');t('橙色难度',x+w-26,y+173,9,'difficulty',align='right')
    t('材料可做 4 次',x+26,y+194,10,'ink')
    t('材料',x+24,y+232,10,'muted')
    t('铜锭',x+24,y+255,11,'ink');t('需要 10 / 拥有 8 / 缺少 2',x+w-24,y+255,10,'warning',align='right')
    rule(x+24,y+280,w-48)
    t('训练师：示例锻造训练师',x+24,y+296,10,'muted')
    btn('在地图查看',x+w-114,y+290,90)
    t('85 / 150 与材料数量为示意；不代表训练或采集实测。',x+24,y+329,8,'quiet')

def chat(x,y,w=462,h=352):
    panel('微信式聊天',x,y,w,h)
    side=133;surface(x,y+36,side,h-36,'bg',alpha=.35)
    t('会话    联系人    群聊',x+12,y+48,8.5,'muted')
    for i,(name,sub) in enumerate([('远行小队','小队 · 2 条未读'),('示例好友','私聊 · 离线'),('公会频道','公会 · 暂无未读')]):
        yy=y+77+i*60
        if i==0:surface(x+7,yy,side-14,50,'raised',4,alpha=.60)
        t(name,x+16,yy+9,10,'ink');t(sub,x+16,yy+29,8,'info' if i==0 else 'muted')
    t('[小队] 远行小队',x+side+16,y+49,11,'info')
    t('示例队友 · 14:32',x+side+16,y+82,9,'muted')
    rect(x+side+16,y+106,232,48,'raised',4);t('先在路口集合，再一起进山。',x+side+28,y+120,10,'ink')
    t('我 · 14:33',x+w-82,y+175,9,'muted')
    rect(x+side+75,y+197,w-side-91,43,'hover',4);t('收到，我已准备好。',x+side+87,y+210,10,'ink')
    rule(x+side+12,y+263,w-side-24)
    t('表情    物品    动作',x+side+16,y+275,9,'muted')
    t('输入消息…',x+side+16,y+302,10,'muted');btn('发送',x+w-74,y+309,60,True)
    t('Enter 发送',x+side+16,y+330,8,'quiet')

def navigator(x,y,w=462,h=352):
    panel('世界向导',x,y,w,h)
    t('找 NPC       我的地点       当前导航',x+14,y+49,10,'muted')
    inputbox('训练师',x+14,y+73,w-28)
    row('示例训练师','锻造训练师 · 示例城镇',x+14,y+115,194,True,'')
    row('示例军需官','声望军需官 · 示例要塞',x+14,y+164,194)
    row('示例旅店老板','旅店 · 示例村落',x+14,y+213,194)
    line(x+218,y+114,x+218,y+287,'line',.6)
    t('示例训练师',x+237,y+118,14,'ink')
    t('锻造训练师',x+237,y+146,10,'muted')
    t('示例城镇  42.9, 69.4',x+237,y+174,10,'muted')
    t('直线距离  320 米',x+237,y+200,11,'ink')
    btn('开始导航',x+237,y+232,108,True);btn('地图',x+353,y+232,60)
    t('收藏地点',x+237,y+275,10,'brand')
    surface(x+14,y+301,w-28,36,'bg',4,alpha=.35)
    t('↑',x+27,y+301,25,'brand');t('示例训练师  ·  前方  ·  320 米（直线）',x+65,y+312,9,'ink')

def targets(x,y,w=462,h=352):
    panel('目标选择',x,y,w,h)
    t('友方    小队    附近',x+14,y+49,10,'ink');t('施法兼容：脱战',x+w-124,y+49,9,'muted')
    names=['晨光','林风','雾松','星河','青川']
    classes=['#F58CBA','#FFFFFF','#ABD473','#69CCF0','#FF7D0A']
    for i,name in enumerate(names):
        xx=x+17+i*83; yy=y+82
        rect(xx,yy,76,70,'raised',2)
        rect(xx+2,yy+30,72,35,'#284238',2)
        t(name,xx+8,yy+10,11,classes[i]);t(['94%','83%','100%','65%','90%'][i],xx+8,yy+40,10,'ink')
        rect(xx+2,yy+65,72,3,'info')
        if i==1:rect(xx,yy,76,70,'raised',2,stroke='target',sw=2);t(name,xx+8,yy+10,11,classes[i]);t('当前目标',xx+8,yy+40,9,'ink')
        if i==3:pdf.setStrokeColor(color('focus'));pdf.setLineWidth(2);pdf.roundRect(xx+3,H-yy-67,70,64,2,stroke=1,fill=0)
    t('敌方 · 公开可见信息',x+17,y+181,10,'muted')
    row('示例敌方单位','生命值 72% · 距离区间 20-25 米',x+14,y+205,w-28,False,'Lv. 18')
    surface(x+14,y+264,w-28,58,'bg',4,alpha=.35)
    t('左键 选中    右键 焦点    Ctrl + 右键 标记',x+26,y+276,10,'ink')
    t('悬停暂缓重排；进入战斗交还临时输入状态。',x+26,y+299,9,'muted')

def macros(x,y,w=462,h=352):
    panel('个人宏工坊',x,y,w,h)
    t('通用      牧师',x+14,y+49,10,'muted')
    for i,s in enumerate(['鼠标指向 · 治疗','鼠标指向 · 敌方','焦点 · 打断','通用 · 设置焦点']):
        yy=y+82+i*43
        if i==0:surface(x+10,yy,142,34,'hover',3,alpha=.60)
        t(s,x+19,yy+10,9,'ink' if i==0 else 'muted')
    xx=x+170
    t('技能一',xx,y+80,10,'muted');inputbox('快速治疗',xx,y+101,165);btn('从法术本选',xx+172,y+102,97)
    t('角色宏名称',xx,y+147,10,'muted');inputbox('MF-治疗',xx,y+168,269)
    t('预览片段 · 实际须完整展示',xx,y+213,10,'muted')
    rect(xx,y+236,269,58,'bg',3)
    t('#showtooltip',xx+9,y+245,9,'ink')
    t('/cast [@mouseover,help,nodead] 快速治疗',xx+9,y+265,8,'ink')
    btn('创建角色宏',xx,y+309,110,True);btn('取到鼠标',xx+118,y+309,90,disabled=True)

def fieldkit(x,y,w=462,h=352):
    panel('随身手册',x,y,w,h)
    t('示例林地',x+24,y+64,20,'ink');t('42.6, 63.1',x+24,y+97,15,'muted')
    t('普通背包空格',x+24,y+147,10,'muted');t('装备耐久',x+252,y+147,10,'muted')
    t('8 格',x+24,y+172,28,'ink');t('93%',x+252,y+172,28,'ink')
    rule(x+24,y+222,w-48)
    t('本次净收支',x+24,y+243,10,'muted');t('+1 金 24 银',x+252,y+240,16,'ink')
    t('本次旅途',x+24,y+284,10,'muted');t('35 分 12 秒',x+252,y+281,16,'ink')
    t('拖动标题移动 · 锁定状态可见 · 关闭不重置统计',x+24,y+325,9,'quiet')

def coach(x,y,w=462,h=352):
    panel('AI 教练 · 本地采集原型',x,y,w,h)
    t('尚未连接 AI',x+14,y+49,10,'warning')
    t('正在采集 · 本会话 86 条',x+14,y+75,13,'success')
    t('数据项',x+14,y+116,10,'muted')
    for j,s in enumerate(['脱战','战斗','副本','PvP']):t(s,x+184+j*63,y+116,9,'muted')
    rows=[('角色基础',['已读到','部分受限','待观察','待观察']),('目标生命',['已读到','受限','待观察','待观察']),('施法事件',['仅见事件','仅见事件','待观察','待观察']),('增益字段',['无数据','受限','待观察','待观察'])]
    for i,(name,values) in enumerate(rows):
        yy=y+148+i*32;t(name,x+14,yy,10,'ink')
        for j,s in enumerate(values):t(s,x+184+j*63,yy,8,'warning' if '受限' in s else ('success' if s=='已读到' else 'muted'))
        rule(x+14,yy+25,w-28)
    t('已读到只表示取得部分字段，不能推断完整支持。',x+14,y+287,9,'muted')
    btn('暂停采集',x+14,y+310,86,True);btn('重新检测',x+108,y+310,86);btn('导出 JSON',x+202,y+310,92);btn('诊断摘要',x+302,y+310,86)

def screenplan(x,y,w,h,mode='default'):
    """Flat screen-clearance schematic, deliberately not a gameplay screenshot."""
    scene(x,y,w,h)
    surface(x,y,w,h,'bg',5,alpha=.25,stroke='line',sw=.7)
    # Reserved native UI: minimap, quest tracker, action/cast region.
    rect(x+w*.84,y+h*.05,w*.13,h*.22,'raised',2)
    t('小地图',x+w*.85,y+h*.12,7,'muted')
    rect(x+w*.84,y+h*.35,w*.13,h*.38,'raised',2)
    t('任务追踪',x+w*.845,y+h*.47,7,'muted')
    rect(x+w*.30,y+h*.85,w*.40,h*.09,'raised',2)
    t('动作条 / 读条',x+w*.38,y+h*.865,7,'muted')
    # The main character/action field stays free of addon panels.
    cx,cy,cw,ch=x+w*.30,y+h*.225,w*.40,h*.55
    pdf.saveState();pdf.setStrokeColor(color('quiet'));pdf.setLineWidth(.8);pdf.setDash(3,3)
    pdf.rect(cx,H-cy-ch,cw,ch,stroke=1,fill=0);pdf.restoreState()
    t('建议净空',cx+cw*.24,cy+ch*.32,11,'ink')
    t('40% 宽 × 55% 高',cx+cw*.13,cy+ch*.58,8,'muted')
    if mode=='expanded':
        surface(x+w*.025,y+h*.10,w*.23,h*.65,'panel',3,alpha=.84,stroke='line',sw=.6)
        t('主动展开',x+w*.045,y+h*.15,9,'ink')
        t('工具主窗',x+w*.045,y+h*.35,8,'muted')
        t('用后收起',x+w*.045,y+h*.53,8,'brand')
    elif mode=='notification':
        surface(x+w*.025,y+h*.13,w*.23,h*.20,'panel',3,alpha=.80)
        t('发现 铜矿',x+w*.045,y+h*.18,9,'success')
        t('同屏仅一条',x+w*.045,y+h*.43,8,'muted')
    elif mode=='combat':
        xx=x+w*.025;yy=y+h*.15;cell=min(18,w*.045)
        t('必要分组',xx,yy-14,8,'muted')
        for i in range(5):
            rect(xx+i*(cell+2),yy,cell,cell,'raised',1)
            rect(xx+i*(cell+2),yy+cell-4,cell,3,'brand')
        t('保持安全权限',xx,yy+cell+10,8,'muted')
    else:
        t('无工具主窗',x+w*.035,y+h*.16,9,'muted')

# 1 cover
page('把画面还给冒险。','原生工具窗与 HUD / 学习 Apple 的清晰与克制，适配魔兽的操作语境',True)
t('默认收起，按需展开。',44,156,31,'ink')
p('原则 1：尽量不占游戏主画面，让画面干净。\n以清晰的控件与反馈建立秩序，不做网页式后台。',44,211,432,14,'muted',24)
t('这份圣经解决三件事',44,326,15,'ink')
for i,v in enumerate(['平时少出现：留出游戏视野','需要时看清：突出当前任务','做完即收起：减少来回操作']):t(v,44,364+i*29,13,'muted')
screenplan(520,158,396,232)
t('默认游戏态 · 净空平面示意',520,406,12,'ink')
t('Chat / Professions / Navigator / Targets',520,438,11,'muted')
t('Macros / FieldKit / Coach',520,463,11,'muted')
note('本文件为设计提案，不代表插件已实现或已经游戏实测。新默认值不覆盖已有用户选择和位置。七插件共享视觉规范，保持独立安装和运行。')
finish()

# 2 principles
page('原则 1：主画面优先，插件按需出现','默认少占屏；工具窗按需展开且背景半透明。保留魔兽图标、语义与操作权限。')
left=[('主画面保持干净','新默认建议不常驻主窗。只在启用导航等有实际需要时保留边缘紧凑信息；不把所有插件同时铺开。'),('内容仍然属于游戏','技能、物品和职业沿用现有图标与语义；保留原生物品提示、链接和必要的品质标识。'),('同一动作，始终同一表达','主按钮表示下一步动作；选中态表示正在查看的对象；状态文字说明结果。不让一种强调色同时承担选中、成功与警告。')]
right=[('新默认不覆盖已有选择','净空范围可调；不自动移动原生界面，不重置已保存位置、显示状态、声音和闪光设置。七插件仍独立使用。'),('界面不改变操作权限','战斗保护、受限字段、地图扫描与临时输入所有权按现有逻辑处理。灰色按钮不能通过视觉改造变成可执行。'),('原生工具感与适度透明','精简工具栏、同层内容；背景适度透明，文字保持清楚。不做网页后台、不以强玻璃或模糊争抢画面。')]
bullets(left,44,158,410);bullets(right,518,158,398)
for title,body in left+right:note(title+'：'+body)
finish()

# Screen clearance and four display modes
page('主画面净空与四种显示状态','平面示意，非游戏截图；中央约 40% 宽 × 55% 高建议留空，可按分辨率和用户布局调整。')
views=[('默认游戏态','default','未操作时无主窗；导航等必要状态才保留紧凑信息。'),('主动展开态','expanded','用户打开后查看或操作，用完收起；主窗避让中央。'),('短时提醒态','notification','同屏一条，同类合并；建议 2-3 秒，保留旧声光设置。'),('战斗态','combat','减少非必要信息；分组与动作沿现有 secure 安全机制。')]
for i,(title,mode,caption) in enumerate(views):
    xx=44+(i%2)*454;yy=152+(i//2)*196
    t(title,xx,yy,13)
    screenplan(xx,yy+24,418,134,mode)
    p(caption,xx,yy+167,418,9.5,'body',14)
note('净空同时避让原生小地图、任务追踪、目标框、动作条和读条；图中虚线仅为文档说明，游戏内不常驻画出。')
note('同屏提醒建议一条，同类合并，建议2-3秒；重要未解决状态保持就近可见。战斗中不临时改变受保护按钮。新默认不覆盖已有用户选择。')
finish()

# 3 palette type
page('视觉基因：中性灰、清字、少量操作蓝','七插件外壳均有透明度；蓝色区分动作与选中，文字与游戏固有语义保持清晰。')
swatches=[('背景','bg'),('面板','panel'),('抬升','raised'),('悬停','hover'),('边界','line')]
for i,(name,key) in enumerate(swatches):
    xx=44+i*92;rect(xx,161,80,58,key,4);t(name,xx,228,10);t(C[key],xx,248,9,'body')
for i,(name,key) in enumerate([('正文','ink'),('次要','muted'),('弱化','quiet'),('选中 / 链接','brand'),('金色点缀','gold')]):
    xx=44+i*92;rect(xx,290,80,42,'panel',4);t('Aa 字',xx+10,299,15,key);t(name,xx,342,10);t(C[key],xx,362,9,'body')
rect(44,414,448,95,'panel',6)
t('选中 / 链接',60,433,11,'brand');t('成功',180,433,11,'success');t('提醒',260,433,11,'warning');t('失败',340,433,11,'danger')
btn('主要操作',60,470,110,True);t('#0A64C5 / 白字',184,475,9,'muted');t('浅蓝小字 #8BBEF3',340,475,9,'muted')
y=158
for a,b in [('窗口标题 16','当前插件与对象'),('正文 13','消息、名称、可读数据'),('辅助文字 12','单位、来源、简短提示'),('紧凑下限 11','只用于非主要内容'),('强调数值 18-20','仅用于少量一眼扫读数据')]:
    t(a,540,y,13);t(b,540,y+25,11,'body');y+=66
t('魔兽语义保留：品质、职业、频道、配方难度；当前目标红框，焦点黄框。',44,530,9,'body')
note('颜色值与 tokens.json 一致。WoW 的字号使用逻辑像素；文档排版大小不等于游戏像素。中文优先客户端现有可读字体，不把外部字库打包进插件。')
finish()

# 4 frame
page('窗口与控件：一套可重复的尺寸','主动展开态示例；4 点间距网格。这里展示工具主窗细节，不代表默认常驻游戏画面。')
professions(44,160,462,352)
y=158
for title,body in [('窗口结构','标题栏 36；工具栏 32；内容内边距 12。右上固定折叠、关闭；拖动仅由标题区开始。'),('点击和输入','按钮高 28 / 32；输入框高 30；图标按钮 28。常用动作采用文字按钮；纯图标必须有提示。'),('列表与密度','普通行高 34，双行详情 44；目标主格保留 56。正文默认 13，不能用缩小字来解决拥挤。'),('圆角与边界','面板 6，控件 4，列表与物品图标 2。边线最多一层；避免边框里再套边框。'),('缩放与拉伸','保留商业技能窗口拉伸和顶部技能书功能。窄窗口减少并列列数、换行辅助文案，不截断核心名称。')]:
    y=block(title,body,548,y,368)
for s in ['标题36 / 工具32 / 内边距12 / 4点网格','按钮28或32 / 输入30 / 图标按钮28','行34 / 双行44 / 目标格56','面板圆角6 / 控件4 / 列表2']:note(s)
finish()

# 5 hierarchy
page('先看对象与下一步，再看解释','默认界面只保留能帮助当前判断的信息；细节按需展开，诊断放到次级入口。')
columns=[44,184,474,736];widths=[130,280,252,180]
headers=['层级','显示什么','视觉方式','放在哪里']
for x,s in zip(columns,headers):t(s,x,160,12)
rows=[('优先 P0','失败、战斗暂停、不能发送','短句 + 状态色 + 恢复动作','相关操作旁'),('主要 P1','当前对象、关键进度、下一步','正文高对比；只留一个主按钮','标题下第一屏'),('辅助 P2','距离、材料数、来源、时间','12 号字；单位齐全；数值对齐','对象下一行'),('细节 P3','完整说明、备选配方、条件','折叠区 / 悬浮提示 / 详情','按需显示'),('诊断 P4','版本、GUID、日志、API字段','诊断摘要 / 导出入口','二级页面')]
y=197
for i,vals in enumerate(rows):
    rect(36,y-7,888,52,'white' if i%2==0 else 'paper',3)
    for j,s in enumerate(vals):p(s,columns[j],y,widths[j],10.5,'body',17)
    y+=61
note('按钮 vs 文字：触发动作或改变状态用按钮；身份、数量、位置、原因用文字；打开一个可识别对象的详情可用交互文字；纯状态不画成按钮。')
finish()

# 6 decisions
page('按钮与文字：让点击行为可预测','不用按钮装饰状态，也不把真正的操作藏成普通灰字。')
items=[('用按钮','发送、开始导航、打开技能书、创建角色宏。动词开头；一个主流程最多一枚蓝底白字主按钮，其他用中性次按钮。'),('用普通文字','85 / 150、直线距离 320 米、缺少 2、离线、待观察、战斗中暂停。状态说明不能看起来像可点击操作。'),('用交互文字','物品名打开原生提示、训练师名查看地图、更多资料展开详情。使用统一强调色，悬停有明确反馈。'),('用开关或分段','持续设置用开关，并显示开/关；互斥页面用标签；动作不做开关，状态不做互斥标签。')]
bullets(items,44,157,410)
rect(522,158,394,354,'panel',6)
t('同一控件的六种状态',542,179,15,'ink')
for i,(name,kind) in enumerate([('默认','normal'),('悬停','hover'),('按下','pressed'),('键盘焦点','focus'),('不可用','disabled'),('执行中','loading')]):
    yy=222+i*43;t(name,542,yy+5,10,'muted')
    if kind=='hover':rect(690,yy,190,27,'hover',4);t('开始导航',750,yy+6,10,'ink')
    elif kind=='pressed':rect(690,yy+1,190,27,'line',4);t('开始导航',750,yy+7,10,'ink')
    elif kind=='focus':rect(688,yy-2,194,31,'panel',5,stroke='brand',sw=1.5);btn('开始导航',690,yy,190)
    else:btn('正在处理…' if kind=='loading' else '开始导航',690,yy,190,disabled=kind=='disabled')
note('禁用要给原因；忙碌要有进行中反馈且阻止重复触发；失败保留输入，成功只在实际得到确认后显示。键盘焦点与鼠标悬停必须可区别。')
finish()

PLUGINS=[
('商业技能助手','我现在该练什么，还缺哪些材料？',professions,[('第一眼','当前专业、进度、建议训练项目、缺料数量。配方难度保留橙 / 黄 / 绿 / 灰，并给文字标签。'),('按钮与文字','打开技能书是动作；85 / 150 是文字；配方行可选中，材料名保留物品链接；训练师入口次于当前配方。'),('最短流程','打开面板 → 选专业或训练项目 → 查看材料 / 打开技能书。展开状态与窗口位置在内容刷新后保留。'),('必须守住','采集提醒只显示确认的新鲜资源名与声音；没有资源方向或自动导航。保留已验收拉伸和顶部技能书。')]),
('微信式聊天','谁在等我回复，怎样准确发送？',chat,[('第一眼','当前会话、未读、消息正文、发送状态。公会 / 小队 / 团队 / 私聊等继续保留频道色与文字标签。'),('按钮与文字','发送按钮固定在输入区；表情、物品、动作属辅助入口；时间和在线状态是文字；会话整行可点。'),('最短流程','点击未读会话 → 输入消息 → Enter / 点击发送。失败时保留草稿，在原位置显示原因与可用的重试入口。'),('必须守住','发送中不画成已发送；离线和不可用状态不靠颜色暗示。折叠或关闭不应静默丢掉草稿。')]),
('世界向导','我要找谁，下一步朝哪里走？',navigator,[('第一眼','当前目标名、用途、区域、直线距离；导航开始后使用紧凑箭头 HUD，主面板可收起。'),('按钮与文字','开始导航为主按钮；地图、收藏为次操作；坐标、直线距离为文字；停止在导航状态中明确出现。'),('最短流程','搜索用途 / NPC → 选结果 → 开始导航。筛选按需展开；已有地点可直接开始；保留原生任务地图入口。'),('必须守住','方向来自实际可用信息；跨区或未知时隐藏失效箭头并写明原因。不得虚构道路路线、到达时间或自动寻路。')]),
('目标选择','我点的是谁，当前目标与焦点是谁？',targets,[('第一眼','姓名职业色、生命值、资源条、当前目标 / 焦点标记。主格保留紧凑尺寸，不增加重复职业文本。'),('按钮与文字','目标格整体是操作区；左键选中，右键焦点，Ctrl + 右键标记。距离区间和受限提示是文字。'),('最短流程','扫读名单 → 指向目标格 → 使用已有点击或技能键。悬停时暂缓所在名单重排，避免光标下换人。'),('必须守住','当前目标红框、焦点黄框；可叠加。脱战临时兼容与战斗原生权限必须区分；未知信息显示未知，不猜测。')]),
('个人宏工坊','这个宏会做什么，创建的是否就是预览？',macros,[('第一眼','模板名、技能参数、完整宏预览、创建结果。正文说明帮助理解目标规则，避免只写术语。'),('按钮与文字','从法术本选、创建角色宏是按钮；角色宏名称是输入；预览为可选复制的只读内容；取到鼠标是创建后步骤。'),('最短流程','选模板 → 选已学技能并看预览 → 创建角色宏。创建成功后再启用取到鼠标，不能默认覆盖同名宏。'),('必须守住','不暗示自动施法；按实际战斗限制禁用创建或变更动作；输入无效时在参数旁解释并保留原值。')]),
('随身手册','背包、耐久和本次旅途是否需要处理？',fieldkit,[('第一眼','普通背包空格、装备耐久优先；区域坐标、旅途净收支与时间按固定顺序显示，单位永远齐全。'),('按钮与文字','主界面以读数为主，不把坐标和耐久画成按钮；关闭和锁定放标题区，避免每一行都加操作。'),('最短流程','打开 → 一眼扫读 → 收起。位置保留；锁定后避免误拖动；关闭不重置本次旅途统计。'),('必须守住','未知用破折号；零就是零。战斗中暂停时显示短状态，不用上一次数据伪装实时更新。')]),
('AI 教练 · 本地原型','哪些公开字段可读，采集是否在进行？',coach,[('第一眼','尚未连接 AI、采集 / 暂停状态、会话条数。能力矩阵保留已读到、部分受限、受限、无数据等真实状态。'),('按钮与文字','暂停 / 继续、重新检测、导出、诊断摘要是动作；场景列名、计数和能力结论是文字。新会话放次级位置。'),('最短流程','打开 → 看状态与矩阵 → 必要时暂停 / 导出。说明关闭只隐藏窗口，不等于停止采集。'),('必须守住','不展示虚构的AI回答或路线建议；待观察不能写成不支持；仅见事件不能写成字段可读；接口拦截时明确暂停。')])]
defaults={'商业技能助手':'默认隐藏 / 收起；仅确认的新鲜资源短提示。','微信式聊天':'默认收起；必要私聊可用单行提示，默认不露正文。','世界向导':'导航未启用时隐藏；启用后仅保留 300 × 84 HUD。','目标选择':'只显示当前需要的分组；保留已有安全机制。','个人宏工坊':'仅主动编辑时打开；编辑完成关闭。','随身手册':'默认隐藏；可选单行，不常驻完整面板。','AI 教练 · 本地原型':'仅主动检测时打开；隐藏不等于暂停采集。'}
for name,question,draw,items in PLUGINS:
    page(name,question+'  /  主动展开态示意，非游戏截图；用后收起。')
    draw(44,158,462,352)
    p('默认态建议：'+defaults[name],44,524,462,9,'body',13)
    t('背景 alpha 0.84 / 透明 16%；仅背景变淡，文字与目标标识保持清楚。',548,530,8.5,'body')
    y=158
    for title,body in items:y=block(title,body,548,y,368)
    for title,body in items:note(title+'：'+body)
    finish()

#14 states
page('状态与提醒：给出结果，也给出退路','短促、局部、可恢复。同屏一条、同类合并，建议 2-3 秒；声音和闪光沿用用户设置。')
states=[('正在读取','保留窗口结构与对象位置；显示“正在读取”，避免把未返回字段写成 0。','info'),('没有内容','解释没有什么，以及何时会出现；有有效入口时提供下一步。','muted'),('操作失败','原因贴近按钮或输入；草稿、参数与列表选中保持，允许明确重试。','danger'),('战斗暂停','说明暂停范围；禁止的动作失效并解释原因。脱战后按现有规则恢复。','warning'),('旧记录 / 受限','旧数据写“上次记录”；未知字段用“未知 / —”；不填假数。','quiet'),('新鲜资源提醒','同屏一条、同类合并；建议 2-3 秒。只报确认的新鲜资源名，保留原声音 / 闪光设置。','brand')]
scene(44,158,872,354)
surface(44,158,872,354,'panel',6,alpha=.84)
for i,(title,body,c) in enumerate(states):
    yy=170+i*56
    t(title,60,yy+7,12,'success' if c=='brand' else c)
    p(body,250,yy+5,646,10.5,'muted',17)
    if i<5:rule(60,yy+49,840)
    note(title+'：'+body)
finish()

#15 interaction
page('操作简便：删掉犹豫，不删除必要确认','点击目标够大、位置稳定、反馈及时；用清楚的动作名称代替用户猜测。')
items=[('默认路径保持在三步内','找对象 → 看关键信息 → 执行动作。常用按钮靠近对象；复杂设置后移，不阻塞主流程。'),('固定位置比动画更重要','刷新不跳回列表顶部，不在悬停时重排；滚动和展开状态尽量保留。错误出现时也不推走用户正在点的按钮。'),('少而清楚的快捷方式','Enter 用于聊天发送；Esc 优先关浮层，再处理输入，最后关窗口。不改全局键位；不默认添加冲突快捷键。')]
y=bullets(items,44,158,410)
items2=[('普通动作即时反馈','悬停 / 按下建议 80-120 ms；菜单建议 120-160 ms。动画只解释状态，不让内容入场表演；支持减少动效。'),('危险动作放慢一步','清空记录、恢复默认、覆盖已有宏等才需要明确确认。普通选中、收起、切页不弹确认。'),('关闭语义写清楚','隐藏窗口、停止导航、暂停采集是不同动作。关闭后保留需要的草稿和位置，恢复自己拥有的临时输入状态。')]
bullets(items2,518,158,398)
for title,body in items+items2:note(title+'：'+body)
finish()

#16 QA
page('落地与验收：先换外壳，再验证动作','这是下一轮开发的验收标准；此轮交付仅为规范和设计预览。')
checkgroups=[('视觉验收',['未操作无主窗；导航等必要信息按需紧凑显示。','缩放 0.85 / 1.00 / 1.25；1080p 与 1440p 下可读。','中央净空；避让小地图、任务、动作条和读条。','品质、职业、频道、配方难度与目标 / 焦点语义保留。']),('操作验收',['四态切换和七插件常用流程走通，失败保留输入。','键盘焦点可见；图标按钮有名称和悬浮提示。','通知同屏一条；未解决状态就近保留，旧设置不覆盖。','进入战斗、死亡、地图变化和失效身份能正确恢复。']),('实施顺序',['先建立视觉 token 和可复用控件，不强制共同依赖。','先改独立本机候选：外壳 → 列表 → 提醒 → 设置。','保留商业技能已验收拉伸和技能书，再逐项游戏验收。','按项目 AGENTS 的发布授权执行；本轮不生成公开发行包。'])]
for i,(title,rows) in enumerate(checkgroups):
    xx=44+i*298;t(title,xx,160,15)
    yy=204
    for s in rows:
        rect(xx,yy+3,8,8,'paper',1,stroke='body',sw=.8)
        yy=p(s,xx+20,yy,250,11,'body',18)+20
rect(44,472,872,56,'white',5)
t('配套文件',60,482,11)
t('ART_BIBLE.md  ·  tokens.json  ·  index.html 交互预览  ·  book.html 阅读版',60,507,10,'body')
note('设计依据：2026-11-11 只读检查七插件当前 UI / README / TOC。浏览器示例不证明游戏渲染、secure 按钮、资源发现或发送动作已实测。')
finish()

# 18 Apple principles, specifically adapted to an independently loaded WoW addon.
page('从 Apple 学清晰，把原生感落在游戏里','学习交互原则与工具秩序；保留魔兽的字体、图标、目标语义和战斗权限。')
headers=['学习什么','如何用于魔兽插件','避免什么']
xs=[44,242,630];ws=[178,366,286]
for xx,v in zip(xs,headers):t(v,xx,154,12)
rows=[('清晰与精简','对象名、关键信息、一个主动作先出现；背景说明按需展开。','网页 Hero、营销式大字、多层内容卡片'),('一致与上下文','控件位置稳定；选中与执行分开；刷新后保留草稿、展开和滚动。','一刷新就跳位；把窗口关闭当作业务停止'),('工具栏只留常用项','搜索、当前筛选与常用指令就近排列；完整设置放次级入口。','把所有功能铺满工具栏或加全家桶侧栏'),('HUD 小而明确','激活导航才出现紧凑浮层；游戏中央尽量净空，异常状态就近显示。','大窗常驻；持续发光；用动画反复争抢注意力')]
for i,vals in enumerate(rows):
    yy=190+i*55
    for j,v in enumerate(vals):p(v,xs[j],yy,ws[j],10.5,'body',17)
    line(44,yy+43,916,yy+43,'lightline',.6)
# A true native-tool fragment: no browser navigation, app suite sidebar, or decorative tiles.
panel('当前导航',44,432,300,84,role='hud')
t('↑',59,469,24,'brand');t('示例训练师',98,474,12,'ink');t('320 米 · 直线',98,496,9,'muted')
t('300 × 84 HUD 示意 · 仅导航激活时出现',44,526,8.5,'body')
t('Apple HIG 官方参考（概括与项目适配，非外观复制）',390,424,10,'black')
refs=[('Design principles','https://developer.apple.com/design/human-interface-guidelines/design-principles/'),('Panels','https://developer.apple.com/design/human-interface-guidelines/panels/'),('Toolbars','https://developer.apple.com/design/human-interface-guidelines/toolbars/'),('Designing for games','https://developer.apple.com/design/human-interface-guidelines/designing-for-games/')]
for i,(label,url) in enumerate(refs):
    yy=449+i*20;t(label,390,yy,9.5,'body');pdf.linkURL(url,(390,H-yy-14,700,H-yy+2),relative=0,thickness=0)
p('不复制交通灯按钮；不打包 SF Symbols 或未经授权字体；不以假实时玻璃效果覆盖游戏。',706,447,210,9.5,'body',16)
for v in rows:note(' / '.join(v))
note('官方参考：'+', '.join(url for _,url in refs))
finish()

# 19 Material and alpha contract. Samples below use PDF fill alpha, not flattened pale colours.
page('所有外壳适度透明，内容始终清楚','alpha 表示不透明度；透明比例 = 1 - alpha。只改变背景，不让文字、图标、生命条或目标标识变淡。')
samples=[('主工具窗',.84,'16%','0.72-0.94'),('紧凑 HUD',.72,'28%','0.60-0.90'),('短时提醒',.80,'20%','0.70-0.92'),('外观 / 上下文浮层',.90,'10%','0.82-0.96')]
for i,(label,a,trans,rng) in enumerate(samples):
    xx=44+i*224
    scene(xx,160,200,132,light=i%2==1)
    surface(xx+9,172,182,108,'panel',6,alpha=a,stroke='line',sw=.8)
    t(label,xx+22,189,12,'ink')
    t('alpha '+format(a,'.2f'),xx+22,222,11,'ink')
    t('透明 '+trans,xx+22,247,10,'muted')
    t('用户可调 alpha '+rng,xx,305,9,'body')
t('绘制规则',44,350,15)
y=380
for title,body in [('背景单独透','只给背景设置 alpha；文字、图标、链接、生命条、目标与焦点保持 alpha 1。'),('子背景保持轻量','不再层叠实心卡片盖满透射层。主按钮可保持不透明，让动作名称清晰；普通边界约 alpha 0.55。')]:
    y=block(title,body,44,y,410)
t('可读性验收',518,350,15)
y=380
for title,body in [('分别叠加深、浅与复杂背景','在默认、最小和最大 alpha 下检查文字、链接和目标标识；亮色或复杂场景可增加局部背板或由用户调高背景 alpha。'),('对比度结论有范围','5.77:1 仅适用于不透明蓝色主按钮与白字；不能据此保证所有半透明合成场景。此处是平面示意，客户端仍需实测。')]:
    y=block(title,body,518,y,398)
for label,a,trans,rng in samples:note(label+' alpha '+str(a)+'，透明 '+trans+'，用户alpha范围 '+rng)
note('不使用父Frame全局SetAlpha；不承诺自动背景识别、自动调参或实时模糊。')
finish()

assert PAGE==19,PAGE
pdf.save()
reader=PdfReader(ROOT/'MyForever-Art-Bible.pdf')
assert len(reader.pages)==19
for i,pg in enumerate(reader.pages):
    txt=pg.extract_text()
    assert txt and '我的无限' in txt,(i,len(txt or ''))
(ROOT/'tmp'/'pdf').mkdir(parents=True,exist_ok=True)
(ROOT/'tmp'/'pdf'/'build-check.json').write_text(json.dumps({'pages':PAGE,'text_width_warnings':WARN,'page_char_counts':[len(p.extract_text()) for p in reader.pages]},ensure_ascii=False,indent=2))
# The book uses the full source bible when it is available. A same-content page fallback keeps it readable.
md=ROOT/'ART_BIBLE.md'
if md.exists():
    source=md.read_text()
    try:
        import markdown
        body=markdown.markdown(source,extensions=['tables','fenced_code'])
    except ImportError:
        try:
            import markdown2
            body=markdown2.markdown(source,extras=['tables','fenced-code-blocks'])
        except ImportError:
            body='<pre>'+html.escape(source)+'</pre>'
else:
    body=''.join('<section><h2>'+html.escape(s['title'])+'</h2><p>'+html.escape(s['subtitle'])+'</p>'+''.join('<p>'+html.escape(v)+'</p>' for v in s['content'])+'</section>' for s in BOOK)
css='''*{box-sizing:border-box}html{background:#111214}body{font:16px/1.75 system-ui,-apple-system,"PingFang SC","Microsoft YaHei",sans-serif;color:#263642;margin:0}header{background:#222326;color:#F5F5F7;padding:16px max(calc((100vw - 1000px)/2),24px)}header h1{font-size:20px;margin:0 0 6px}header p{color:#C0C3C9;font-size:13px;margin:6px 0 12px}nav{display:flex;gap:24px;flex-wrap:wrap}nav a{color:#8BBEF3;font-size:13px}main{max-width:1080px;margin:0 auto;background:#F4F6F7;padding:36px 44px 60px}h1{font-size:28px}h2{font-size:24px;margin:48px 0 18px;page-break-before:auto}h3{font-size:19px;margin-top:30px}h4{font-size:17px}table{border-collapse:collapse;width:100%;font-size:14px;margin:22px 0;display:block;overflow:auto}th,td{padding:11px 13px;text-align:left;border-bottom:1px solid #D4DDE2;vertical-align:top;min-width:100px}th{background:#E5EBEE;color:#17232D}code{font:13px ui-monospace,monospace;overflow-wrap:anywhere}pre{white-space:pre-wrap;background:#E5EBEE;padding:20px;overflow:auto}a{color:#165AA6}li{margin:6px 0}blockquote{border-left:3px solid #0A64C5;margin:24px 0;padding:10px 20px;background:#E8EFF7}hr{border:0;border-top:1px solid #D4DDE2;margin:32px 0}@media(max-width:600px){main{padding:24px 20px}header h1{font-size:20px}}@media print{html{background:white}header{padding:20px 0;color:#17232D;background:white}header p{color:#425462}nav{display:none}main{padding:0;max-width:none;background:white;font-size:10pt}h2,h3{break-after:avoid}tr{break-inside:avoid}a{color:inherit;text-decoration:none}}'''
book='<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>我的无限 · 静石 | 美术圣经</title><style>'+css+'</style></head><body><header><h1>我的无限 · 静石</h1><p>七个自研插件的统一 UI / UX 美术圣经 · 原生工具窗提案 v1.2 · 2026.11.11</p><nav><a href="index.html">打开交互预览</a><a href="MyForever-Art-Bible.pdf">查看 19 页图文手册</a><a href="ART_BIBLE.md">规范源文件</a></nav></header><main>'+body+'</main></body></html>'
(ROOT/'book.html').write_text(book)
print(json.dumps({'pdf':str(ROOT/'MyForever-Art-Bible.pdf'),'pages':PAGE,'width_warnings':WARN,'book_uses_full_bible':md.exists()},ensure_ascii=False))
