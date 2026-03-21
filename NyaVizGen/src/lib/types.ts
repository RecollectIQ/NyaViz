// Types for NyaViz Generator

export interface LyricLine {
  id: string;
  text: string;
  words: Word[];
  startTime: number | null; // in milliseconds
  endTime: number | null;
  secondaryText?: string; // for translations/echoes
  markedForReview?: boolean; // flag for potential timing errors
}

export interface Word {
  id: string;
  text: string;
  color: string | null; // hex color or null for default
  isBold: boolean;
  isItalic: boolean;
}

export interface TimingSession {
  isActive: boolean;
  currentLineIndex: number;
  pressStartTime: number | null;
}

export interface ColorPreset {
  name: string;
  hex: string;
}

export const DEFAULT_COLOR_PRESETS: ColorPreset[] = [
  { name: 'red', hex: '#ef4444' },
  { name: 'orange', hex: '#f97316' },
  { name: 'gold', hex: '#fbbf24' },
  { name: 'yellow', hex: '#facc15' },
  { name: 'lime', hex: '#84cc16' },
  { name: 'green', hex: '#22c55e' },
  { name: 'teal', hex: '#14b8a6' },
  { name: 'cyan', hex: '#06b6d4' },
  { name: 'blue', hex: '#3b82f6' },
  { name: 'indigo', hex: '#6366f1' },
  { name: 'violet', hex: '#8b5cf6' },
  { name: 'purple', hex: '#a855f7' },
  { name: 'fuchsia', hex: '#d946ef' },
  { name: 'pink', hex: '#ec4899' },
  { name: 'crimson', hex: '#dc143c' },
  { name: 'white', hex: '#ffffff' },
];

// Generate unique ID
export function generateId(): string {
  return Math.random().toString(36).substring(2, 11);
}

// Parse lyrics text into lines
export function parseLyrics(text: string): LyricLine[] {
  const lines = text.split('\n').filter(line => line.trim().length > 0);
  return lines.map(line => ({
    id: generateId(),
    text: line.trim(),
    words: parseWordsFromLine(line.trim()),
    startTime: null,
    endTime: null,
  }));
}

// Parse a line into individual words, separating leading/trailing punctuation
// Apostrophes adjacent to word characters stay with the word (e.g., "can't", "askin'", "'cause")
export function parseWordsFromLine(line: string): Word[] {
  const tokens = line.split(/(\s+)/).filter(w => w.length > 0);
  const result: Word[] = [];
  
  for (const token of tokens) {
    // If it's whitespace, add as-is
    if (/^\s+$/.test(token)) {
      result.push({
        id: generateId(),
        text: token,
        color: null,
        isBold: false,
        isItalic: false,
      });
      continue;
    }
    
    // Extract leading punctuation
    // Stop if we hit a word char, or an apostrophe followed by a word char
    let i = 0;
    while (i < token.length) {
      const char = token[i];
      const nextChar = token[i + 1];
      
      if (/\w/.test(char)) break;
      if (char === "'" && nextChar && /\w/.test(nextChar)) break;
      
      i++;
    }
    const leadingPunct = token.slice(0, i);
    
    // Extract trailing punctuation
    // Stop if we hit a word char, or an apostrophe preceded by a word char
    let j = token.length - 1;
    while (j >= i) {
      const char = token[j];
      const prevChar = token[j - 1];
      
      if (/\w/.test(char)) break;
      if (char === "'" && prevChar && /\w/.test(prevChar)) break;
      
      j--;
    }
    const trailingPunct = token.slice(j + 1);
    const wordContent = token.slice(i, j + 1);
    
    // Add leading punctuation as separate token
    if (leadingPunct) {
      result.push({
        id: generateId(),
        text: leadingPunct,
        color: null,
        isBold: false,
        isItalic: false,
      });
    }
    
    // Add the word content (includes apostrophes adjacent to letters)
    if (wordContent) {
      result.push({
        id: generateId(),
        text: wordContent,
        color: null,
        isBold: false,
        isItalic: false,
      });
    }
    
    // Add trailing punctuation as separate token
    if (trailingPunct) {
      result.push({
        id: generateId(),
        text: trailingPunct,
        color: null,
        isBold: false,
        isItalic: false,
      });
    }
  }
  
  return result;
}

// Format time as HH:MM:SS,mmm
export function formatTime(ms: number): string {
  // Round to integer milliseconds
  const totalMs = Math.round(ms);
  const hours = Math.floor(totalMs / 3600000);
  const minutes = Math.floor((totalMs % 3600000) / 60000);
  const seconds = Math.floor((totalMs % 60000) / 1000);
  const milliseconds = totalMs % 1000;
  
  return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')},${milliseconds.toString().padStart(3, '0')}`;
}

// Format time for display (MM:SS)
export function formatTimeDisplay(ms: number): string {
  const minutes = Math.floor(ms / 60000);
  const seconds = Math.floor((ms % 60000) / 1000);
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

// Parse SRT file content into LyricLines with timing
export function parseSRT(content: string): LyricLine[] {
  // Normalize line endings and remove BOM
  const normalized = content.replace(/\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const blocks = normalized.split(/\n\n+/).filter(b => b.trim().length > 0);

  const lines: LyricLine[] = [];

  for (const block of blocks) {
    const blockLines = block.trim().split('\n');

    // Find the timestamp line (contains " --> ")
    let timestampIdx = -1;
    for (let i = 0; i < blockLines.length; i++) {
      if (blockLines[i].includes('-->')) {
        timestampIdx = i;
        break;
      }
    }

    if (timestampIdx === -1) continue;

    // Parse timestamps
    const timestampLine = blockLines[timestampIdx];
    const match = timestampLine.match(/(\d{1,2}:?\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{1,2}:?\d{2}:\d{2}[,\.]\d{3})/);
    if (!match) continue;

    const startTime = parseSRTTimestamp(match[1]);
    const endTime = parseSRTTimestamp(match[2]);

    // Collect text lines after the timestamp
    const textLines = blockLines.slice(timestampIdx + 1).filter(l => l.trim().length > 0);
    if (textLines.length === 0) continue;

    // Strip HTML tags and ASS tags
    const text = textLines
      .map(l => l.replace(/<[^>]+>/g, '').replace(/\{\\[^}]+\}/g, '').trim())
      .join(' ');

    if (!text) continue;

    lines.push({
      id: generateId(),
      text,
      words: parseWordsFromLine(text),
      startTime,
      endTime,
    });
  }

  return lines;
}

// Parse SRT timestamp string to milliseconds
function parseSRTTimestamp(ts: string): number {
  // Replace comma with period for consistency
  ts = ts.replace(',', '.');

  const parts = ts.split(':');
  let hours = 0, minutes = 0, seconds = 0;

  if (parts.length === 3) {
    hours = parseInt(parts[0], 10);
    minutes = parseInt(parts[1], 10);
    seconds = parseFloat(parts[2]);
  } else if (parts.length === 2) {
    minutes = parseInt(parts[0], 10);
    seconds = parseFloat(parts[1]);
  }

  return Math.round((hours * 3600 + minutes * 60 + seconds) * 1000);
}

// Generate NyaViz file content
export function generateNyaVizContent(lines: LyricLine[]): string {
  const timedLines = lines.filter(line => line.startTime !== null && line.endTime !== null);
  
  let output = '';
  let sequenceNumber = 1;
  
  for (const line of timedLines) {
    output += `${sequenceNumber}\n`;
    output += `${formatTime(line.startTime!)} --> ${formatTime(line.endTime!)}\n`;
    output += formatLineWithStyles(line) + '\n\n';
    
    // Add secondary line if present
    if (line.secondaryText) {
      output += `${formatTime(line.startTime!)} --> ${formatTime(line.endTime!)}\n`;
      output += `(${line.secondaryText})\n\n`;
    }
    
    sequenceNumber++;
  }
  
  return output.trim();
}

// Format a line with color/style markers
function formatLineWithStyles(line: LyricLine): string {
  let result = '';
  
  for (const word of line.words) {
    let styledWord = word.text;
    
    // Build style tags
    const styles: string[] = [];
    if (word.color) styles.push(word.color);
    if (word.isBold) styles.push('b');
    if (word.isItalic) styles.push('i');
    
    if (styles.length > 0) {
      const styleStr = styles.join(' ');
      styledWord = `[${styleStr}]${word.text}[/]`;
    }
    
    result += styledWord;
  }
  
  return result;
}

