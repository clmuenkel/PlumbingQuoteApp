import {
  computeOptionTotals,
} from "./pricing.ts";

Deno.test("computeOptionTotals excludes labor line from taxable subtotal", () => {
  const totals = computeOptionTotals(
    [
      { name: "PVC Pipe", total: 100.0 },
      { name: "Labor", total: 999.0 },
      { name: "Valve", total: 25.25 },
    ],
    2,
    { laborRatePerHour: 95, taxRate: 0.0825 },
  );

  if (totals.subtotal !== 125.25) throw new Error(`Expected subtotal 125.25, got ${totals.subtotal}`);
  if (totals.laborTotal !== 190) throw new Error(`Expected laborTotal 190, got ${totals.laborTotal}`);
  if (totals.tax !== 10.33) throw new Error(`Expected tax 10.33, got ${totals.tax}`);
  if (totals.total !== 325.58) throw new Error(`Expected total 325.58, got ${totals.total}`);
});

Deno.test("computeOptionTotals uses configured tax rate and rounds to cents", () => {
  const totals = computeOptionTotals(
    [
      { name: "Part A", total: 19.999 },
      { name: "Part B", total: 10.005 },
    ],
    1.5,
    { laborRatePerHour: 110.137, taxRate: 0.0775 },
  );

  if (totals.subtotal !== 30) throw new Error(`Expected subtotal 30, got ${totals.subtotal}`);
  if (totals.laborTotal !== 165.21) throw new Error(`Expected laborTotal 165.21, got ${totals.laborTotal}`);
  if (totals.tax !== 2.33) throw new Error(`Expected tax 2.33, got ${totals.tax}`);
  if (totals.total !== 197.54) throw new Error(`Expected total 197.54, got ${totals.total}`);
});
