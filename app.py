from __future__ import annotations

import math
import random
import threading
from dataclasses import dataclass
from pathlib import Path
from tkinter import (
    BOTH,
    DISABLED,
    HORIZONTAL,
    LEFT,
    NORMAL,
    RIGHT,
    X,
    Button,
    Canvas,
    DoubleVar,
    Frame,
    IntVar,
    Label,
    OptionMenu,
    Scale,
    StringVar,
    Tk,
    filedialog,
    messagebox,
)

import numpy as np
from PIL import Image, ImageChops, ImageEnhance, ImageOps, ImageTk


APP_TITLE = "Slitscan Found Image Lab"
MODES = (
    "Vertical Time Slits",
    "Horizontal Time Slits",
    "Diagonal Tear",
    "Radial Scan",
    "Wave Loom",
    "Torn Contact Sheet",
)
IMAGE_TYPES = (
    ("Images", "*.png *.jpg *.jpeg *.bmp *.gif *.tif *.tiff *.webp"),
    ("All files", "*.*"),
)


@dataclass
class RenderSettings:
    mode: str
    slit_width: int
    drift: int
    blend: float
    wave: int
    phase: int
    grain: int
    color_shift: int


def fit_image(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    fitted = ImageOps.contain(image.convert("RGB"), size)
    canvas = Image.new("RGB", size, (9, 10, 12))
    canvas.paste(fitted, ((size[0] - fitted.width) // 2, (size[1] - fitted.height) // 2))
    return canvas


def prepare_pair(a: Image.Image, b: Image.Image, max_edge: int = 1400) -> tuple[Image.Image, Image.Image]:
    width = min(max(a.width, b.width), max_edge)
    height = min(max(a.height, b.height), max_edge)
    ratio = min(max_edge / max(width, height), 1.0)
    size = (max(1, int(width * ratio)), max(1, int(height * ratio)))
    return fit_image(a, size), fit_image(b, size)


def color_shift(image: Image.Image, amount: int) -> Image.Image:
    if amount == 0:
        return image
    r, g, b = image.split()
    r = ImageChops.offset(r, amount, 0)
    b = ImageChops.offset(b, -amount, 0)
    return Image.merge("RGB", (r, g, b))


def add_grain(array: np.ndarray, amount: int) -> np.ndarray:
    if amount <= 0:
        return array
    noise = np.random.default_rng().normal(0, amount, array.shape)
    return np.clip(array.astype(np.float32) + noise, 0, 255).astype(np.uint8)


def render_slitscan(a: Image.Image, b: Image.Image, settings: RenderSettings) -> Image.Image:
    a, b = prepare_pair(a, b)
    a = color_shift(a, settings.color_shift)
    b = color_shift(b, -settings.color_shift)

    arr_a = np.asarray(a, dtype=np.uint8)
    arr_b = np.asarray(b, dtype=np.uint8)
    height, width, _ = arr_a.shape
    out = np.empty_like(arr_a)

    slit = max(1, settings.slit_width)
    drift = settings.drift
    wave = settings.wave
    phase = settings.phase / 100.0 * math.tau
    blend = np.clip(settings.blend / 100.0, 0.0, 1.0)

    if settings.mode == "Vertical Time Slits":
        for x in range(width):
            wobble = int(math.sin((x / max(1, slit)) * 0.45 + phase) * wave)
            source_x = (x + drift + wobble) % width
            use_b = ((x // slit) % 2) == 1
            out[:, x] = arr_b[:, source_x] if use_b else arr_a[:, x]

    elif settings.mode == "Horizontal Time Slits":
        for y in range(height):
            wobble = int(math.sin((y / max(1, slit)) * 0.45 + phase) * wave)
            source_y = (y + drift + wobble) % height
            use_b = ((y // slit) % 2) == 1
            out[y, :] = arr_b[source_y, :] if use_b else arr_a[y, :]

    elif settings.mode == "Diagonal Tear":
        yy, xx = np.indices((height, width))
        tear = ((xx + yy + drift + (np.sin(yy * 0.035 + phase) * wave)) // slit).astype(int)
        mask = (tear % 2) == 0
        shifted_x = (xx + drift + (np.sin(yy * 0.05 + phase) * wave).astype(int)) % width
        sampled_b = arr_b[yy, shifted_x]
        out = np.where(mask[..., None], arr_a, sampled_b)

    elif settings.mode == "Radial Scan":
        cy, cx = height / 2.0, width / 2.0
        yy, xx = np.indices((height, width))
        distance = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        angle = np.arctan2(yy - cy, xx - cx)
        ripple = np.sin(angle * 9 + phase) * wave
        rings = ((distance + ripple + drift) // slit).astype(int)
        mask = (rings % 2) == 0
        offset_x = np.clip((xx + np.cos(angle) * drift).astype(int), 0, width - 1)
        offset_y = np.clip((yy + np.sin(angle) * drift).astype(int), 0, height - 1)
        sampled_b = arr_b[offset_y, offset_x]
        out = np.where(mask[..., None], arr_a, sampled_b)

    elif settings.mode == "Wave Loom":
        yy, xx = np.indices((height, width))
        wave_x = (np.sin(yy * 0.025 + phase) * (wave + drift)).astype(int)
        wave_y = (np.cos(xx * 0.025 + phase) * wave).astype(int)
        sample_x = (xx + wave_x) % width
        sample_y = (yy + wave_y) % height
        band = (((xx + wave_x) // slit) + ((yy + wave_y) // slit)) % 2 == 0
        sampled_a = arr_a[sample_y, xx]
        sampled_b = arr_b[yy, sample_x]
        out = np.where(band[..., None], sampled_a, sampled_b)

    else:
        random.seed(settings.phase + settings.drift + settings.slit_width)
        out[:] = arr_a
        x = 0
        while x < width:
            strip_width = random.randint(max(1, slit // 2), max(1, slit * 3))
            source_x = (x + random.randint(-drift, drift) if drift else x) % width
            end = min(width, x + strip_width)
            source_end = min(width, source_x + (end - x))
            pasted = arr_b[:, source_x:source_end]
            if pasted.shape[1] < end - x:
                pasted = np.concatenate((pasted, arr_b[:, : end - x - pasted.shape[1]]), axis=1)
            vertical_shift = random.randint(-wave, wave) if wave else 0
            out[:, x:end] = np.roll(pasted, vertical_shift, axis=0)
            x = end

    if blend > 0:
        mixed = (out.astype(np.float32) * (1.0 - blend)) + (arr_b.astype(np.float32) * blend)
        out = np.clip(mixed, 0, 255).astype(np.uint8)

    out = add_grain(out, settings.grain)
    result = Image.fromarray(out, "RGB")
    if settings.grain or settings.color_shift:
        result = ImageEnhance.Contrast(result).enhance(1.03)
    return result


class SlitscanApp:
    def __init__(self, root: Tk) -> None:
        self.root = root
        self.root.title(APP_TITLE)
        self.root.minsize(1040, 720)

        self.image_a: Image.Image | None = None
        self.image_b: Image.Image | None = None
        self.result: Image.Image | None = None
        self.preview_photo: ImageTk.PhotoImage | None = None
        self.render_after: str | None = None
        self.is_rendering = False
        self.pending_render = False

        self.mode = StringVar(value=MODES[0])
        self.slit_width = IntVar(value=18)
        self.drift = IntVar(value=60)
        self.blend = DoubleVar(value=18)
        self.wave = IntVar(value=34)
        self.phase = IntVar(value=0)
        self.grain = IntVar(value=7)
        self.color_shift_value = IntVar(value=4)
        self.status = StringVar(value="Load two images to begin.")
        self.a_label = StringVar(value="Image A: empty")
        self.b_label = StringVar(value="Image B: empty")

        self.build_ui()
        self.root.bind("<Configure>", lambda _event: self.refresh_preview())

    def build_ui(self) -> None:
        shell = Frame(self.root, bg="#111318")
        shell.pack(fill=BOTH, expand=True)

        sidebar = Frame(shell, width=300, bg="#191c22", padx=14, pady=14)
        sidebar.pack(side=LEFT, fill="y")
        sidebar.pack_propagate(False)

        stage = Frame(shell, bg="#0b0c0f", padx=14, pady=14)
        stage.pack(side=RIGHT, fill=BOTH, expand=True)

        Label(sidebar, text=APP_TITLE, fg="#f3efe7", bg="#191c22", font=("Helvetica", 18, "bold")).pack(anchor="w")
        Label(sidebar, text="Two-source slit experiments", fg="#aeb6c2", bg="#191c22").pack(anchor="w", pady=(2, 18))

        Button(sidebar, text="Load Image A", command=lambda: self.load_image("a"), height=2).pack(fill=X, pady=(0, 8))
        Label(sidebar, textvariable=self.a_label, fg="#c9d0da", bg="#191c22", wraplength=260, justify=LEFT).pack(anchor="w", pady=(0, 10))

        Button(sidebar, text="Load Image B", command=lambda: self.load_image("b"), height=2).pack(fill=X, pady=(0, 8))
        Label(sidebar, textvariable=self.b_label, fg="#c9d0da", bg="#191c22", wraplength=260, justify=LEFT).pack(anchor="w", pady=(0, 18))

        Label(sidebar, text="Scan Mode", fg="#f3efe7", bg="#191c22", font=("Helvetica", 12, "bold")).pack(anchor="w")
        menu = OptionMenu(sidebar, self.mode, *MODES, command=lambda _value: self.schedule_render())
        menu.pack(fill=X, pady=(4, 12))

        self.add_slider(sidebar, "Slit Width", self.slit_width, 1, 120)
        self.add_slider(sidebar, "Drift", self.drift, -300, 300)
        self.add_slider(sidebar, "Blend Back", self.blend, 0, 100)
        self.add_slider(sidebar, "Wave", self.wave, 0, 180)
        self.add_slider(sidebar, "Phase", self.phase, 0, 100)
        self.add_slider(sidebar, "Grain", self.grain, 0, 40)
        self.add_slider(sidebar, "Color Shift", self.color_shift_value, -40, 40)

        action_bar = Frame(sidebar, bg="#191c22")
        action_bar.pack(fill=X, pady=(14, 8))
        Button(action_bar, text="Randomize", command=self.randomize).pack(side=LEFT, fill=X, expand=True, padx=(0, 6))
        Button(action_bar, text="Export", command=self.export, state=DISABLED).pack(side=LEFT, fill=X, expand=True, padx=(6, 0))
        self.export_button = action_bar.winfo_children()[1]

        Button(sidebar, text="Reset Controls", command=self.reset_controls).pack(fill=X)
        Label(sidebar, textvariable=self.status, fg="#99d7c2", bg="#191c22", wraplength=260, justify=LEFT).pack(anchor="w", pady=(18, 0))

        self.canvas = Canvas(stage, bg="#0b0c0f", highlightthickness=0)
        self.canvas.pack(fill=BOTH, expand=True)

    def add_slider(self, parent: Frame, label: str, variable: IntVar | DoubleVar, minimum: int, maximum: int) -> None:
        Label(parent, text=label, fg="#dfe5ee", bg="#191c22").pack(anchor="w", pady=(8, 0))
        scale = Scale(
            parent,
            from_=minimum,
            to=maximum,
            orient=HORIZONTAL,
            variable=variable,
            command=lambda _value: self.schedule_render(),
            bg="#191c22",
            fg="#f3efe7",
            troughcolor="#313743",
            highlightthickness=0,
        )
        scale.pack(fill=X)

    def settings(self) -> RenderSettings:
        return RenderSettings(
            mode=self.mode.get(),
            slit_width=self.slit_width.get(),
            drift=self.drift.get(),
            blend=float(self.blend.get()),
            wave=self.wave.get(),
            phase=self.phase.get(),
            grain=self.grain.get(),
            color_shift=self.color_shift_value.get(),
        )

    def load_image(self, slot: str) -> None:
        path = filedialog.askopenfilename(title=f"Choose Image {slot.upper()}", filetypes=IMAGE_TYPES)
        if not path:
            return

        try:
            image = Image.open(path).convert("RGB")
        except Exception as exc:
            messagebox.showerror(APP_TITLE, f"Could not load that image.\n\n{exc}")
            return

        if slot == "a":
            self.image_a = image
            self.a_label.set(f"Image A: {Path(path).name}")
        else:
            self.image_b = image
            self.b_label.set(f"Image B: {Path(path).name}")

        self.status.set("Ready." if self.image_a and self.image_b else "Load the second image to begin.")
        self.schedule_render()

    def randomize(self) -> None:
        self.mode.set(random.choice(MODES))
        self.slit_width.set(random.randint(2, 70))
        self.drift.set(random.randint(-220, 220))
        self.blend.set(random.randint(0, 45))
        self.wave.set(random.randint(0, 140))
        self.phase.set(random.randint(0, 100))
        self.grain.set(random.randint(0, 28))
        self.color_shift_value.set(random.randint(-22, 22))
        self.schedule_render()

    def reset_controls(self) -> None:
        self.mode.set(MODES[0])
        self.slit_width.set(18)
        self.drift.set(60)
        self.blend.set(18)
        self.wave.set(34)
        self.phase.set(0)
        self.grain.set(7)
        self.color_shift_value.set(4)
        self.schedule_render()

    def schedule_render(self) -> None:
        if not (self.image_a and self.image_b):
            self.draw_empty_state()
            return
        if self.render_after:
            self.root.after_cancel(self.render_after)
        self.render_after = self.root.after(120, self.render_async)

    def render_async(self) -> None:
        self.render_after = None
        if not (self.image_a and self.image_b):
            return
        if self.is_rendering:
            self.pending_render = True
            return

        self.is_rendering = True
        self.status.set("Rendering...")
        settings = self.settings()
        image_a = self.image_a.copy()
        image_b = self.image_b.copy()

        def worker() -> None:
            try:
                result = render_slitscan(image_a, image_b, settings)
            except Exception as exc:
                self.root.after(0, lambda: self.render_failed(exc))
                return
            self.root.after(0, lambda: self.render_done(result))

        threading.Thread(target=worker, daemon=True).start()

    def render_done(self, result: Image.Image) -> None:
        self.result = result
        self.is_rendering = False
        self.export_button.configure(state=NORMAL)
        self.status.set(f"Rendered {result.width} x {result.height}.")
        self.refresh_preview()
        if self.pending_render:
            self.pending_render = False
            self.schedule_render()

    def render_failed(self, exc: Exception) -> None:
        self.is_rendering = False
        self.status.set("Render failed.")
        messagebox.showerror(APP_TITLE, f"Render failed.\n\n{exc}")

    def refresh_preview(self) -> None:
        if not self.result:
            self.draw_empty_state()
            return

        width = max(100, self.canvas.winfo_width() - 20)
        height = max(100, self.canvas.winfo_height() - 20)
        preview = ImageOps.contain(self.result, (width, height))
        self.preview_photo = ImageTk.PhotoImage(preview)
        self.canvas.delete("all")
        self.canvas.create_image(
            self.canvas.winfo_width() // 2,
            self.canvas.winfo_height() // 2,
            image=self.preview_photo,
            anchor="center",
        )

    def draw_empty_state(self) -> None:
        self.canvas.delete("all")
        self.canvas.create_text(
            self.canvas.winfo_width() // 2,
            self.canvas.winfo_height() // 2,
            text="Load Image A and Image B",
            fill="#8892a0",
            font=("Helvetica", 20, "bold"),
        )

    def export(self) -> None:
        if not self.result:
            return
        path = filedialog.asksaveasfilename(
            title="Export slitscan image",
            defaultextension=".png",
            filetypes=(("PNG", "*.png"), ("JPEG", "*.jpg *.jpeg")),
        )
        if not path:
            return
        try:
            self.result.save(path)
        except Exception as exc:
            messagebox.showerror(APP_TITLE, f"Could not save the image.\n\n{exc}")
            return
        self.status.set(f"Exported {Path(path).name}.")


def main() -> None:
    root = Tk()
    app = SlitscanApp(root)
    app.draw_empty_state()
    root.mainloop()


if __name__ == "__main__":
    main()
