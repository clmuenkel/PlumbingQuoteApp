export type PricingConfig = {
  laborRatePerHour: number;
  taxRate: number;
};

export type LineRow = {
  name: string;
  total: number;
};

export type OptionTotals = {
  subtotal: number;
  laborTotal: number;
  tax: number;
  total: number;
};

export function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function isLaborLine(name: string): boolean {
  return name.trim().toLowerCase() === "labor";
}

export function computeOptionTotals(
  lineRows: LineRow[],
  laborHours: number,
  pricingConfig: PricingConfig,
): OptionTotals {
  const subtotal = round2(
    lineRows
      .filter((row) => !isLaborLine(String(row.name ?? "")))
      .reduce((sum, row) => sum + Number(row.total), 0),
  );
  const clampedLaborHours = Math.max(0, Number(laborHours || 0));
  const laborTotal = round2(clampedLaborHours * pricingConfig.laborRatePerHour);
  const tax = round2(subtotal * pricingConfig.taxRate);
  const total = round2(subtotal + laborTotal + tax);

  return { subtotal, laborTotal, tax, total };
}
