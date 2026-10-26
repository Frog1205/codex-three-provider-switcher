#!/usr/bin/env python3
"""
为 Codex 三线路切换器生成图标：
- 背景：ChatGPT 品牌色 #10A37F 圆角矩形
- 主体：白色 ChatGPT 风格六瓣螺旋花瓣 logo
- 锁：右下角小白色锁形（叠加在 logo 上，提示"锁定/切换/安全"）

输出：多分辨率 .ico (16/32/48/64/128/256)
"""
import math
from PIL import Image, ImageDraw

# 调色板
BG_GREEN = (16, 163, 127)
WHITE = (255, 255, 255)

SIZES = [16, 32, 48, 64, 128, 256]


def draw_chatgpt_knot(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, color=WHITE):
    """绘制 ChatGPT 风格的六瓣螺旋花瓣 logo（简化抽象版）。

    ChatGPT logo 由 6 条交织曲线构成花瓣/结形。
    这里用 6 个细长椭圆围绕中心旋转 + 中心结点 — 形成"六瓣花"轮廓，
    视觉上接近 ChatGPT 标志的螺旋花瓣意象。
    """
    petal_count = 6
    # 每片花瓣：纤细纺锤形（更尖更长），更接近 ChatGPT logo 视觉
    petal_length = r * 1.7
    petal_width = r * 0.22  # 更窄 → 花瓣更尖锐/纤细
    for i in range(petal_count):
        angle = i * (360 / petal_count)
        # 用 rotated ellipse：先画水平椭圆再旋转
        bbox = (-petal_length / 2, -petal_width / 2,
                petal_length / 2, petal_width / 2)
        # PIL ellipse 不直接支持旋转，把椭圆画到一个临时图层再 rotate-paste
        # 简化方案：直接在画布上画水平椭圆，然后用 PIL 旋转粘贴
        # 但 ImageDraw 不支持 → 改用 polygon + chord 近似"花瓣"形
        # 这里采用 polygon 画"叶尖形"：沿椭圆周长取 16 个点
        pts = []
        for k in range(24):
            t = k / 23 * 2 * math.pi
            # 椭圆参数：a=长半轴，b=短半轴
            a = petal_length / 2
            b = petal_width / 2
            # 标准椭圆点：(a*cos(t), b*sin(t))
            ex = a * math.cos(t)
            ey = b * math.sin(t)
            # 旋转 angle（弧度）+ 平移到 (cx, cy)
            rad = math.radians(angle - 90)
            rx = ex * math.cos(rad) - ey * math.sin(rad)
            ry = ex * math.sin(rad) + ey * math.cos(rad)
            pts.append((cx + rx, cy + ry))
        draw.polygon(pts, fill=color + (255,))

    # 中心结点（一个小圆遮盖花瓣重叠区域，使 logo 更聚合）
    dot_r = r * 0.10
    draw.ellipse(
        (cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r),
        fill=color + (255,),
    )


def draw_lock_small(draw: ImageDraw.ImageDraw, cx: float, cy: float, scale: float, color=WHITE):
    """在 (cx, cy) 处画一个小锁（占 scale 比例的画面）"""
    body_w = scale * 0.6
    body_h = scale * 0.4
    body_x0 = cx - body_w / 2
    body_y0 = cy - body_h / 2 + scale * 0.05
    body_radius = scale * 0.06
    draw.rounded_rectangle(
        (body_x0, body_y0, body_x0 + body_w, body_y0 + body_h),
        radius=body_radius,
        fill=color + (255,),
    )
    # 锁梁（半圆 + 短边）
    shackle_w = scale * 0.36
    shackle_thick = scale * 0.07
    shackle_top = body_y0 - scale * 0.18
    s_left = cx - shackle_w / 2
    s_right = cx + shackle_w / 2
    # 半圆
    draw.pieslice(
        (s_left, shackle_top, s_right, shackle_top + shackle_w),
        180, 360, fill=color + (255,)
    )
    # 两侧短边
    draw.rectangle(
        (s_left, shackle_top + shackle_w / 2,
         s_right, body_y0),
        fill=color + (255,),
    )
    # 挖空内环
    inner_w = shackle_w - shackle_thick * 2
    inner_left = cx - inner_w / 2
    inner_right = cx + inner_w / 2
    inner_top = shackle_top + shackle_thick
    draw.pieslice(
        (inner_left, inner_top, inner_right, inner_top + inner_w),
        180, 360, fill=(0, 0, 0, 0)
    )
    draw.rectangle(
        (inner_left, inner_top + inner_w / 2,
         inner_right, body_y0),
        fill=(0, 0, 0, 0),
    )
    # 锁孔
    keyhole_r = scale * 0.045
    draw.ellipse(
        (cx - keyhole_r, cy - keyhole_r - scale * 0.02,
         cx + keyhole_r, cy + keyhole_r - scale * 0.02),
        fill=BG_GREEN + (255,),
    )


def draw_icon(canvas: Image.Image, size: int) -> None:
    w = size
    draw = ImageDraw.Draw(canvas)
    # 圆角绿色背景
    radius = int(w * 0.22)
    pad = int(w * 0.02)
    draw.rounded_rectangle((pad, pad, w - pad, w - pad), radius=radius, fill=BG_GREEN + (255,))

    # 顶部高光
    highlight = int(w * 0.10)
    draw.rounded_rectangle((pad, pad, w - pad, pad + highlight), radius=radius, fill=(255, 255, 255, 30))

    # ChatGPT 风格六瓣螺旋 logo（中央）
    cx, cy = w / 2, w / 2
    r = w * 0.38
    draw_chatgpt_knot(draw, cx, cy, r, color=WHITE)

    # 右下角小锁（叠加，提示"切换/锁定"语义）
    lock_cx = w * 0.74
    lock_cy = w * 0.74
    lock_scale = w * 0.34
    # 先画一个绿色小圆背景让锁独立可读
    badge_r = w * 0.18
    draw.ellipse(
        (lock_cx - badge_r, lock_cy - badge_r, lock_cx + badge_r, lock_cy + badge_r),
        fill=(12, 122, 96, 255),  # 深一点的绿色
    )
    draw_lock_small(draw, lock_cx, lock_cy, lock_scale, color=WHITE)


def main():
    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw_icon(canvas, 256)

    # 大图 PNG 预览
    canvas.save("codex-switcher-icon-preview.png")

    # 多分辨率 .ico
    sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    canvas.save(
        "codex-switcher-icon.ico",
        format="ICO",
        sizes=sizes,
    )
    print(f"wrote codex-switcher-icon.ico with sizes: {sizes}")


if __name__ == "__main__":
    main()