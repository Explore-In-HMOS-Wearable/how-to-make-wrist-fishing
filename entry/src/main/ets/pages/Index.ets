import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PullDetector } from '../game/PullDetector';
import { RandomGenerator } from '../game/RandomGenerator';

const PULL_WINDOW_MS: number = 1000;
const BITE_MS: number = 60;
const WAIT_MIN_MS: number = 2000;
const WAIT_MAX_MS: number = 5000;
const CAUGHT_MS: number = 1600;
const ESCAPED_MS: number = 1200;
const RESET_MS: number = 520;
const FRAME_MS: number = 32;
const DT: number = 0.032;
const FISH_JUMP_MS: number = 620;
const BITE_VIBRATION_MS: number = 35;
const CATCH_VIBRATION_MS: number = 60;
const GRAVITY: number = 430;

enum Phase {
  WAITING,
  BITE,
  PULL_WINDOW,
  CAUGHT,
  ESCAPED,
  RESETTING
}

class Ripple {
  active: boolean = false;
  x: number = 0;
  y: number = 0;
  t: number = 0;
  life: number = 0.9;
}

class Droplet {
  active: boolean = false;
  x: number = 0;
  y: number = 0;
  vx: number = 0;
  vy: number = 0;
  t: number = 0;
  life: number = 0.6;
}

function drawFish(ctx: CanvasRenderingContext2D, x: number, y: number, s: number,
  angle: number, alpha: number, body: string, fin: string): void {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.translate(x, y);
  ctx.rotate(angle);
  ctx.scale(s, Math.cos(angle) < 0 ? -s : s);
  ctx.beginPath();
  ctx.moveTo(-13, 0);
  ctx.lineTo(-26, -10);
  ctx.lineTo(-22, 0);
  ctx.lineTo(-26, 10);
  ctx.closePath();
  ctx.fillStyle = fin;
  ctx.fill();
  ctx.beginPath();
  ctx.moveTo(-1, -7);
  ctx.lineTo(-9, -17);
  ctx.lineTo(3, -9);
  ctx.closePath();
  ctx.fillStyle = fin;
  ctx.fill();
  ctx.beginPath();
  ctx.ellipse(0, 0, 16, 9, 0, 0, Math.PI * 2);
  ctx.fillStyle = body;
  ctx.fill();
  ctx.beginPath();
  ctx.arc(9, -2.6, 1.9, 0, Math.PI * 2);
  ctx.fillStyle = '#0E2230';
  ctx.fill();
  ctx.restore();
}

@Entry
@Component
struct Index {
  @State bannerText: string = '';
  @State bannerSub: string = '';
  @State bannerColor: string = '#5CE08A';
  @State bannerOpacity: number = 0;
  @State bannerScale: number = 0.7;
  @State pullOpacity: number = 0;
  @State titleOpacity: number = 0.85;

  private phase: Phase = Phase.WAITING;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private detector: PullDetector = new PullDetector(() => {
    this.onPull();
  });
  private random: RandomGenerator = new RandomGenerator();
  private frameTimer: number = -1;
  private phaseTimer: number = -1;
  private phaseStart: number = Date.now();
  private biteTime: number = 0;
  private canvasReady: boolean = false;
  private t: number = 0;
  private lastBob: number = 0;
  private lastSag: number = 22;
  private resetBob: number = 0;
  private resetSag: number = 22;
  private lastResult: Phase = Phase.WAITING;
  private skyGrad: CanvasGradient | null = null;
  private waterGrad: CanvasGradient | null = null;
  private ripples: Ripple[] = [new Ripple(), new Ripple(), new Ripple(), new Ripple()];
  private droplets: Droplet[] = [new Droplet(), new Droplet(), new Droplet(), new Droplet(),
    new Droplet(), new Droplet(), new Droplet(), new Droplet(), new Droplet(), new Droplet()];

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.onCanvasReady();
        })

      Column() {
        Column() {
          Text('WRIST FISHING')
            .fontSize(12)
            .fontColor('#7BA8CC')
            .letterSpacing(2)
            .opacity(this.titleOpacity)
          Text('PULL!')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFD24A')
            .opacity(this.pullOpacity)
            .margin({ top: 2 })
        }
        .width('70%')
        .height('26%')
        .justifyContent(FlexAlign.End)

        Blank()

        Column() {
          Text(this.bannerText)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.bannerColor)
          Text(this.bannerSub)
            .fontSize(13)
            .fontColor('#CFE4F2')
            .margin({ top: 2 })
        }
        .width('76%')
        .height('30%')
        .justifyContent(FlexAlign.Start)
        .opacity(this.bannerOpacity)
        .scale({ x: this.bannerScale, y: this.bannerScale })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#08111E')
  }

  onPageShow(): void {
    this.detector.start();
    this.startLoop();
    if (this.canvasReady) {
      this.enterWaiting();
    }
  }

  onPageHide(): void {
    this.suspend();
  }

  aboutToDisappear(): void {
    this.suspend();
  }

  private suspend(): void {
    this.detector.stop();
    this.stopLoop();
    this.clearPhaseTimer();
  }

  private onCanvasReady(): void {
    this.canvasReady = true;
    const w: number = this.ctx.width;
    const h: number = this.ctx.height;
    if (w > 0 && h > 0) {
      this.buildGradients(w, h);
    }
    this.detector.start();
    this.startLoop();
    this.enterWaiting();
  }

  private buildGradients(w: number, h: number): void {
    const sky: CanvasGradient = this.ctx.createLinearGradient(0, 0, 0, h * 0.58);
    sky.addColorStop(0, '#081524');
    sky.addColorStop(1, '#173A5A');
    this.skyGrad = sky;
    const water: CanvasGradient = this.ctx.createLinearGradient(0, h * 0.58, 0, h);
    water.addColorStop(0, '#1D6C99');
    water.addColorStop(1, '#05192C');
    this.waterGrad = water;
  }

  private startLoop(): void {
    if (this.frameTimer === -1) {
      this.frameTimer = setInterval(() => {
        this.draw();
      }, FRAME_MS);
    }
  }

  private stopLoop(): void {
    if (this.frameTimer !== -1) {
      clearInterval(this.frameTimer);
      this.frameTimer = -1;
    }
  }

  private clearPhaseTimer(): void {
    if (this.phaseTimer !== -1) {
      clearTimeout(this.phaseTimer);
      this.phaseTimer = -1;
    }
  }

  private setPhase(next: Phase): void {
    this.phase = next;
    this.phaseStart = Date.now();
  }

  private enterWaiting(): void {
    this.clearPhaseTimer();
    this.detector.disarm();
    this.bannerText = '';
    this.bannerSub = '';
    this.bannerOpacity = 0;
    this.bannerScale = 0.7;
    this.setPhase(Phase.WAITING);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.titleOpacity = 0.85;
      this.pullOpacity = 0;
    });
    const delay: number = this.random.rangeInt(WAIT_MIN_MS, WAIT_MAX_MS);
    this.phaseTimer = setTimeout(() => {
      this.enterBite();
    }, delay);
  }

  private enterBite(): void {
    this.clearPhaseTimer();
    this.setPhase(Phase.BITE);
    this.biteTime = Date.now();
    this.spawnRipple(0.5, 0.58);
    this.vibrate(BITE_VIBRATION_MS);
    this.phaseTimer = setTimeout(() => {
      this.enterPullWindow();
    }, BITE_MS);
  }

  private enterPullWindow(): void {
    this.clearPhaseTimer();
    this.setPhase(Phase.PULL_WINDOW);
    this.detector.arm();
    this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
      this.pullOpacity = 1;
      this.titleOpacity = 0;
    });
    this.phaseTimer = setTimeout(() => {
      this.enterEscaped();
    }, PULL_WINDOW_MS);
  }

  private onPull(): void {
    if (this.phase !== Phase.PULL_WINDOW) {
      return;
    }
    this.enterCaught(Date.now() - this.biteTime);
  }

  private enterCaught(reaction: number): void {
    this.clearPhaseTimer();
    this.detector.disarm();
    this.lastResult = Phase.CAUGHT;
    this.setPhase(Phase.CAUGHT);
    this.spawnDroplets(0.5, 0.58);
    this.vibrate(CATCH_VIBRATION_MS);
    this.bannerText = 'CAUGHT!';
    this.bannerSub = `${reaction} ms`;
    this.bannerColor = '#5CE08A';
    this.showBanner();
    this.phaseTimer = setTimeout(() => {
      this.enterResetting();
    }, CAUGHT_MS);
  }

  private enterEscaped(): void {
    this.clearPhaseTimer();
    this.detector.disarm();
    this.lastResult = Phase.ESCAPED;
    this.setPhase(Phase.ESCAPED);
    this.spawnRipple(0.5, 0.58);
    this.bannerText = 'ESCAPED!';
    this.bannerSub = '';
    this.bannerColor = '#FF8071';
    this.showBanner();
    this.phaseTimer = setTimeout(() => {
      this.enterResetting();
    }, ESCAPED_MS);
  }

  private enterResetting(): void {
    this.clearPhaseTimer();
    this.resetBob = this.lastBob;
    this.resetSag = this.lastSag;
    this.setPhase(Phase.RESETTING);
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.bannerOpacity = 0;
      this.bannerScale = 0.85;
      this.pullOpacity = 0;
    });
    this.phaseTimer = setTimeout(() => {
      this.enterWaiting();
    }, RESET_MS);
  }

  private showBanner(): void {
    this.bannerOpacity = 0;
    this.bannerScale = 0.7;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.ExtremeDeceleration }, () => {
      this.bannerOpacity = 1;
      this.bannerScale = 1;
      this.pullOpacity = 0;
    });
  }

  private vibrate(duration: number): void {
    const effect: vibrator.VibrateTime = { type: 'time', duration: duration };
    const attribute: vibrator.VibrateAttribute = { id: 0, usage: 'notification' };
    vibrator.startVibration(effect, attribute).catch((err: BusinessError) => {
      console.error(`WristFishing vibration failed: ${err.code}`);
    });
  }

  private spawnRipple(rx: number, ry: number): void {
    for (let i = 0; i < this.ripples.length; i++) {
      const r: Ripple = this.ripples[i];
      if (!r.active) {
        r.active = true;
        r.x = rx;
        r.y = ry;
        r.t = 0;
        r.life = 0.95;
        return;
      }
    }
  }

  private spawnDroplets(rx: number, ry: number): void {
    let spawned: number = 0;
    for (let i = 0; i < this.droplets.length && spawned < 8; i++) {
      const d: Droplet = this.droplets[i];
      if (!d.active) {
        d.active = true;
        d.x = rx;
        d.y = ry;
        d.vx = this.random.range(-85, 85);
        d.vy = -this.random.range(130, 280);
        d.t = 0;
        d.life = this.random.range(0.5, 0.8);
        spawned++;
      }
    }
  }

  private updateParticles(w: number, h: number): void {
    for (let i = 0; i < this.ripples.length; i++) {
      const r: Ripple = this.ripples[i];
      if (r.active) {
        r.t += DT;
        if (r.t >= r.life) {
          r.active = false;
        }
      }
    }
    for (let i = 0; i < this.droplets.length; i++) {
      const d: Droplet = this.droplets[i];
      if (d.active) {
        d.t += DT;
        d.vy += GRAVITY * DT;
        d.x += (d.vx * DT) / w;
        d.y += (d.vy * DT) / h;
        if (d.t >= d.life) {
          d.active = false;
        }
      }
    }
  }

  private waveAt(x: number): number {
    return Math.sin(x * 0.034 + this.t * 1.15) * 2.6 + Math.sin(x * 0.017 - this.t * 0.72) * 3.4;
  }

  private easeOut(p: number): number {
    const q: number = 1 - p;
    return 1 - q * q * q;
  }

  private easeInOut(p: number): number {
    return p < 0.5 ? 2 * p * p : 1 - 2 * (1 - p) * (1 - p);
  }

  private bobberOffset(el: number, h: number): number {
    const idle: number = Math.sin(this.t * 1.7) * 3;
    if (this.phase === Phase.WAITING) {
      return idle;
    }
    if (this.phase === Phase.BITE) {
      return 3 + this.easeOut(Math.min(1, el / 200)) * 16;
    }
    if (this.phase === Phase.PULL_WINDOW) {
      return 19 + Math.sin(this.t * 26) * 1.4;
    }
    if (this.phase === Phase.CAUGHT) {
      const p: number = this.easeOut(Math.min(1, el / 340));
      return 19 - p * (19 + h * 0.24);
    }
    if (this.phase === Phase.ESCAPED) {
      if (el < 140) {
        return 19 + (el / 140) * 9;
      }
      const k: number = el - 140;
      return 28 * Math.exp(-k / 240) * Math.cos(k / 95);
    }
    const rp: number = this.easeInOut(Math.min(1, el / RESET_MS));
    return this.resetBob * (1 - rp) + idle * rp;
  }

  private lineSag(el: number): number {
    if (this.phase === Phase.WAITING) {
      return 22 + Math.sin(this.t * 1.3) * 1.6;
    }
    if (this.phase === Phase.BITE) {
      return 22 - Math.min(1, el / 200) * 8;
    }
    if (this.phase === Phase.PULL_WINDOW) {
      return 14;
    }
    if (this.phase === Phase.CAUGHT) {
      return 14 * (1 - this.easeOut(Math.min(1, el / 180)));
    }
    if (this.phase === Phase.ESCAPED) {
      const p: number = Math.min(1, el / 520);
      return 14 + p * 14 + Math.sin(el / 70) * 2.2 * (1 - p);
    }
    const rp: number = this.easeInOut(Math.min(1, el / RESET_MS));
    return this.resetSag * (1 - rp) + 22 * rp;
  }

  private draw(): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const w: number = ctx.width;
    const h: number = ctx.height;
    if (w < 1 || h < 1) {
      return;
    }
    if (this.skyGrad === null || this.waterGrad === null) {
      this.buildGradients(w, h);
    }

    this.t += DT;
    const el: number = Date.now() - this.phaseStart;
    const waterY: number = h * 0.58;
    const bx: number = w * 0.5;
    const bob: number = this.bobberOffset(el, h);
    const sag: number = this.lineSag(el);
    this.lastBob = bob;
    this.lastSag = sag;
    const by: number = waterY + bob;

    this.updateParticles(w, h);

    ctx.globalAlpha = 1;
    ctx.fillStyle = this.skyGrad !== null ? this.skyGrad : '#0A1526';
    ctx.fillRect(0, 0, w, h);

    this.drawWater(ctx, w, h, waterY);
    if (this.phase === Phase.WAITING) {
      this.drawAmbientFish(ctx, w, waterY);
    }
    if (this.phase === Phase.ESCAPED) {
      this.drawEscapingFish(ctx, bx, waterY, el);
    }
    this.drawRipples(ctx, w, h);
    this.drawLine(ctx, w, h, bx, by, sag);
    this.drawBobber(ctx, bx, by);
    this.drawDroplets(ctx, w, h);
    this.drawJumpFish(ctx, w, h, bx, waterY, el);
  }

  private drawWater(ctx: CanvasRenderingContext2D, w: number, h: number, waterY: number): void {
    ctx.beginPath();
    ctx.moveTo(0, h);
    for (let x = 0; x <= w; x += 10) {
      ctx.lineTo(x, waterY + this.waveAt(x));
    }
    ctx.lineTo(w, h);
    ctx.closePath();
    ctx.fillStyle = this.waterGrad !== null ? this.waterGrad : '#0E3350';
    ctx.fill();

    ctx.beginPath();
    ctx.moveTo(0, waterY + this.waveAt(0));
    for (let x = 10; x <= w; x += 10) {
      ctx.lineTo(x, waterY + this.waveAt(x));
    }
    ctx.strokeStyle = 'rgba(158,224,255,0.34)';
    ctx.lineWidth = 1.6;
    ctx.stroke();
  }

  private drawAmbientFish(ctx: CanvasRenderingContext2D, w: number, waterY: number): void {
    const span: number = w + 130;
    const x: number = ((this.t * 20) % span) - 65;
    const y: number = waterY + 64 + Math.sin(this.t * 1.1) * 4;
    drawFish(ctx, x, y, 0.5, 0.06, 0.16, '#0B2C43', '#0B2C43');
  }

  private drawEscapingFish(ctx: CanvasRenderingContext2D, bx: number, waterY: number, el: number): void {
    const p: number = Math.min(1, el / 760);
    drawFish(ctx, bx + 14 - 58 * p, waterY + 12 + 76 * p, 0.62, 2.6, 0.45 * (1 - p), '#0A2739', '#0A2739');
  }

  private drawRipples(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    for (let i = 0; i < this.ripples.length; i++) {
      const r: Ripple = this.ripples[i];
      if (!r.active) {
        continue;
      }
      const p: number = r.t / r.life;
      const rx: number = 7 + 48 * p;
      ctx.save();
      ctx.globalAlpha = (1 - p) * 0.55;
      ctx.beginPath();
      ctx.ellipse(r.x * w, r.y * h, rx, rx * 0.32, 0, 0, Math.PI * 2);
      ctx.strokeStyle = '#A8E4FF';
      ctx.lineWidth = 1.4;
      ctx.stroke();
      ctx.restore();
    }
  }

  private drawDroplets(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    for (let i = 0; i < this.droplets.length; i++) {
      const d: Droplet = this.droplets[i];
      if (!d.active) {
        continue;
      }
      ctx.save();
      ctx.globalAlpha = Math.max(0, 1 - d.t / d.life) * 0.8;
      ctx.beginPath();
      ctx.arc(d.x * w, d.y * h, 2.4, 0, Math.PI * 2);
      ctx.fillStyle = '#CDEEFF';
      ctx.fill();
      ctx.restore();
    }
  }

  private drawLine(ctx: CanvasRenderingContext2D, w: number, h: number,
    bx: number, by: number, sag: number): void {
    const ax: number = w * 0.78;
    const ay: number = h * 0.15;
    const mx: number = (ax + bx) / 2;
    const my: number = (ay + by) / 2 + sag;
    ctx.beginPath();
    ctx.moveTo(ax, ay);
    ctx.quadraticCurveTo(mx, my, bx, by - 15);
    ctx.strokeStyle = 'rgba(226,240,252,0.72)';
    ctx.lineWidth = 1.3;
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(ax, ay, 2.6, 0, Math.PI * 2);
    ctx.fillStyle = '#9FB9CF';
    ctx.fill();
  }

  private drawBobber(ctx: CanvasRenderingContext2D, bx: number, by: number): void {
    ctx.beginPath();
    ctx.moveTo(bx, by - 7);
    ctx.lineTo(bx, by - 16);
    ctx.strokeStyle = '#E6EDF3';
    ctx.lineWidth = 1.6;
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(bx, by, 7.5, 0, Math.PI * 2);
    ctx.fillStyle = '#F3F5F7';
    ctx.fill();
    ctx.beginPath();
    ctx.arc(bx, by, 7.5, Math.PI, Math.PI * 2);
    ctx.fillStyle = '#E5453C';
    ctx.fill();
    ctx.beginPath();
    ctx.arc(bx - 2.4, by - 2.4, 1.5, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255,255,255,0.75)';
    ctx.fill();
  }

  private drawJumpFish(ctx: CanvasRenderingContext2D, w: number, h: number,
    bx: number, waterY: number, el: number): void {
    let alpha: number = 1;
    let e: number = el;
    if (this.phase === Phase.RESETTING) {
      if (this.lastResult !== Phase.CAUGHT) {
        return;
      }
      alpha = 1 - Math.min(1, el / RESET_MS);
      e = CAUGHT_MS + el;
    } else if (this.phase !== Phase.CAUGHT) {
      return;
    }

    const x0: number = bx;
    const y0: number = waterY + 4;
    const cx: number = bx - w * 0.27;
    const cy: number = h * 0.10;
    const x2: number = w * 0.5;
    const y2: number = h * 0.34;

    const p: number = Math.min(1, e / FISH_JUMP_MS);
    const q: number = 1 - p;
    const fx: number = q * q * x0 + 2 * q * p * cx + p * p * x2;
    let fy: number = q * q * y0 + 2 * q * p * cy + p * p * y2;
    let angle: number = Math.atan2(2 * q * (cy - y0) + 2 * p * (y2 - cy),
      2 * q * (cx - x0) + 2 * p * (x2 - cx));

    if (p >= 1) {
      const hold: number = e - FISH_JUMP_MS;
      const b: number = Math.min(1, hold / 260);
      const endAngle: number = Math.atan2(2 * (y2 - cy), 2 * (x2 - cx));
      angle = endAngle * (1 - b) + Math.sin(hold / 240) * 0.14 * b;
      fy += Math.sin(hold / 260) * 3.5;
    }

    const scale: number = 0.6 + 0.4 * Math.min(1, p / 0.45);
    drawFish(ctx, fx, fy, scale, angle, alpha, '#5FC9E8', '#3AA7CC');
  }
}
