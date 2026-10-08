import { sensor } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';

const SAMPLE_INTERVAL_NS: number = 20000000;
const GRAVITY_ALPHA: number = 0.10;
const SIGNAL_ALPHA: number = 0.45;
const GYRO_ALPHA: number = 0.40;
const DEAD_ZONE: number = 0.9;
const RISE_THRESHOLD: number = 3.2;
const RELEASE_THRESHOLD: number = 1.4;
const PEAK_UP_THRESHOLD: number = 6.5;
const PEAK_MAG_THRESHOLD: number = 7.0;
const GYRO_THRESHOLD: number = 1.1;
const MIN_DURATION_MS: number = 50;
const MAX_DURATION_MS: number = 420;
const COOLDOWN_MS: number = 700;

export class PullDetector {
  private onPull: () => void;
  private accelOn: boolean = false;
  private gyroOn: boolean = false;
  private armed: boolean = false;
  private hasGravity: boolean = false;
  private gx: number = 0;
  private gy: number = 0;
  private gz: number = 0;
  private ax: number = 0;
  private ay: number = 0;
  private az: number = 0;
  private gyroMag: number = 0;
  private gyroPeak: number = 0;
  private rising: boolean = false;
  private needRelease: boolean = true;
  private riseStart: number = 0;
  private peakUp: number = 0;
  private peakMag: number = 0;
  private cooldownUntil: number = 0;

  private accelCallback: (data: sensor.AccelerometerResponse) => void =
    (data: sensor.AccelerometerResponse) => {
      this.onAccel(data.x, data.y, data.z);
    };

  private gyroCallback: (data: sensor.GyroscopeResponse) => void =
    (data: sensor.GyroscopeResponse) => {
      const m: number = Math.sqrt(data.x * data.x + data.y * data.y + data.z * data.z);
      this.gyroMag += GYRO_ALPHA * (m - this.gyroMag);
    };

  constructor(onPull: () => void) {
    this.onPull = onPull;
  }

  start(): void {
    if (!this.accelOn) {
      try {
        sensor.on(sensor.SensorId.ACCELEROMETER, this.accelCallback, { interval: SAMPLE_INTERVAL_NS });
        this.accelOn = true;
      } catch (err) {
        console.error(`WristFishing accelerometer unavailable: ${(err as BusinessError).code}`);
      }
    }
    if (!this.gyroOn) {
      try {
        sensor.on(sensor.SensorId.GYROSCOPE, this.gyroCallback, { interval: SAMPLE_INTERVAL_NS });
        this.gyroOn = true;
      } catch (err) {
        console.error(`WristFishing gyroscope unavailable: ${(err as BusinessError).code}`);
      }
    }
  }

  stop(): void {
    if (this.accelOn) {
      try {
        sensor.off(sensor.SensorId.ACCELEROMETER, this.accelCallback);
      } catch (err) {
        console.error(`WristFishing accelerometer off failed: ${(err as BusinessError).code}`);
      }
      this.accelOn = false;
    }
    if (this.gyroOn) {
      try {
        sensor.off(sensor.SensorId.GYROSCOPE, this.gyroCallback);
      } catch (err) {
        console.error(`WristFishing gyroscope off failed: ${(err as BusinessError).code}`);
      }
      this.gyroOn = false;
    }
    this.armed = false;
    this.rising = false;
    this.hasGravity = false;
    this.gyroMag = 0;
  }

  arm(): void {
    this.armed = true;
    this.rising = false;
    this.needRelease = true;
    this.peakUp = 0;
    this.peakMag = 0;
    this.gyroPeak = 0;
  }

  disarm(): void {
    this.armed = false;
    this.rising = false;
  }

  private onAccel(x: number, y: number, z: number): void {
    if (!this.hasGravity) {
      this.gx = x;
      this.gy = y;
      this.gz = z;
      this.hasGravity = true;
      return;
    }
    this.gx += GRAVITY_ALPHA * (x - this.gx);
    this.gy += GRAVITY_ALPHA * (y - this.gy);
    this.gz += GRAVITY_ALPHA * (z - this.gz);

    this.ax += SIGNAL_ALPHA * ((x - this.gx) - this.ax);
    this.ay += SIGNAL_ALPHA * ((y - this.gy) - this.ay);
    this.az += SIGNAL_ALPHA * ((z - this.gz) - this.az);

    if (!this.armed) {
      this.rising = false;
      return;
    }

    const gm: number = Math.sqrt(this.gx * this.gx + this.gy * this.gy + this.gz * this.gz);
    if (gm < 1) {
      return;
    }

    let up: number = (this.ax * this.gx + this.ay * this.gy + this.az * this.gz) / gm;
    if (Math.abs(up) < DEAD_ZONE) {
      up = 0;
    }
    const mag: number = Math.sqrt(this.ax * this.ax + this.ay * this.ay + this.az * this.az);
    const now: number = Date.now();

    if (now < this.cooldownUntil) {
      return;
    }

    if (this.needRelease) {
      if (up < RELEASE_THRESHOLD) {
        this.needRelease = false;
      }
      return;
    }

    if (!this.rising) {
      if (up >= RISE_THRESHOLD) {
        this.rising = true;
        this.riseStart = now;
        this.peakUp = up;
        this.peakMag = mag;
        this.gyroPeak = this.gyroMag;
      }
      return;
    }

    if (up > this.peakUp) {
      this.peakUp = up;
    }
    if (mag > this.peakMag) {
      this.peakMag = mag;
    }
    if (this.gyroMag > this.gyroPeak) {
      this.gyroPeak = this.gyroMag;
    }

    const duration: number = now - this.riseStart;
    const rotationOk: boolean = !this.gyroOn || this.gyroPeak >= GYRO_THRESHOLD;
    const valid: boolean = duration >= MIN_DURATION_MS && duration <= MAX_DURATION_MS &&
      this.peakUp >= PEAK_UP_THRESHOLD && this.peakMag >= PEAK_MAG_THRESHOLD && rotationOk;

    if (valid) {
      this.armed = false;
      this.rising = false;
      this.needRelease = true;
      this.cooldownUntil = now + COOLDOWN_MS;
      this.onPull();
      return;
    }

    if (up < RELEASE_THRESHOLD || duration > MAX_DURATION_MS) {
      this.rising = false;
      this.needRelease = true;
    }
  }
}
