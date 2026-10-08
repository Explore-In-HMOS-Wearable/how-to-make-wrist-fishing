const UINT32_RANGE: number = 4294967296;

export class RandomGenerator {
  private state: number;

  constructor(seed: number = Date.now()) {
    const s: number = seed >>> 0;
    this.state = s === 0 ? 1 : s;
  }

  next(): number {
    let x: number = this.state;
    x ^= x << 13;
    x ^= x >>> 17;
    x ^= x << 5;
    this.state = x >>> 0;
    return this.state / UINT32_RANGE;
  }

  range(min: number, max: number): number {
    return min + this.next() * (max - min);
  }

  rangeInt(min: number, max: number): number {
    return Math.floor(this.range(min, max));
  }
}
