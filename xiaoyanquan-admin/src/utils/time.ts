function pad(value: number): string {
  return String(value).padStart(2, '0');
}

export function formatDateTime(value?: string): string {
  if (!value) return '-';
  const raw = value.trim();
  if (!raw) return '-';

  const matched = raw.match(
    /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$/,
  );
  if (matched) {
    const [, year, month, day, hour = '00', minute = '00', second = '00'] = matched;
    return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
  }

  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return raw;
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}
