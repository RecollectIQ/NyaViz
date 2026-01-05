'use client';

import React, { useState } from 'react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Button } from '@/components/ui/button';
import { DEFAULT_COLOR_PRESETS } from '@/lib/types';

interface ColorPickerProps {
  selectedColor: string | null;
  onColorSelect: (color: string | null) => void;
  disabled?: boolean;
}

// Icons
const Icons = {
  palette: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M4.098 19.902a3.75 3.75 0 005.304 0l6.401-6.402M6.75 21A3.75 3.75 0 013 17.25V4.125C3 3.504 3.504 3 4.125 3h5.25c.621 0 1.125.504 1.125 1.125v4.072M6.75 21a3.75 3.75 0 003.75-3.75V8.197M6.75 21h13.125c.621 0 1.125-.504 1.125-1.125v-5.25c0-.621-.504-1.125-1.125-1.125h-4.072M10.5 8.197l2.88-2.88c.438-.439 1.15-.439 1.59 0l3.712 3.713c.44.44.44 1.152 0 1.59l-2.879 2.88M6.75 17.25h.008v.008H6.75v-.008z" />
    </svg>
  ),
  trash: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
    </svg>
  ),
};

export function ColorPicker({ selectedColor, onColorSelect, disabled }: ColorPickerProps) {
  const [customColor, setCustomColor] = useState('#6b7280');
  const [isOpen, setIsOpen] = useState(false);

  return (
    <Popover open={isOpen} onOpenChange={setIsOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          disabled={disabled}
          className="w-9 h-9 p-0 border-[var(--border)] rounded-lg transition-all hover:bg-[var(--gray-700)] disabled:opacity-30"
          style={{
            borderColor: selectedColor || 'var(--border)',
            backgroundColor: selectedColor ? `${selectedColor}15` : 'transparent',
          }}
        >
          {selectedColor ? (
            <div
              className="w-5 h-5 rounded"
              style={{ backgroundColor: selectedColor }}
            />
          ) : (
            <span className="text-[var(--muted-foreground)]">{Icons.palette}</span>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-64 p-4 bg-[var(--gray-850)] border-[var(--border)] shadow-soft-lg">
        <div className="space-y-4">
          <div className="text-sm font-medium text-[var(--foreground)]">Select Color</div>
          
          {/* Preset Colors Grid */}
          <div className="grid grid-cols-8 gap-2">
            {DEFAULT_COLOR_PRESETS.map((preset) => (
              <button
                key={preset.name}
                onClick={() => {
                  onColorSelect(preset.hex);
                  setIsOpen(false);
                }}
                className={`color-swatch w-6 h-6 rounded border transition-all ${
                  selectedColor === preset.hex ? 'border-white ring-1 ring-white/50 scale-110' : 'border-transparent hover:scale-105'
                }`}
                style={{ backgroundColor: preset.hex }}
                title={preset.name}
              />
            ))}
          </div>

          {/* Custom Color */}
          <div className="flex items-center gap-2">
            <input
              type="color"
              value={customColor}
              onChange={(e) => setCustomColor(e.target.value)}
              className="w-8 h-8 rounded cursor-pointer border border-[var(--border)] bg-transparent"
            />
            <input
              type="text"
              value={customColor}
              onChange={(e) => {
                const val = e.target.value;
                if (/^#[0-9A-Fa-f]{0,6}$/.test(val)) {
                  setCustomColor(val);
                }
              }}
              className="flex-1 px-2 py-1.5 text-sm font-mono bg-[var(--gray-800)] border border-[var(--border)] rounded text-[var(--foreground)]"
              placeholder="#RRGGBB"
            />
            <Button
              size="sm"
              onClick={() => {
                if (/^#[0-9A-Fa-f]{6}$/.test(customColor)) {
                  onColorSelect(customColor);
                  setIsOpen(false);
                }
              }}
              className="btn-primary text-[var(--foreground)]"
            >
              Apply
            </Button>
          </div>

          {/* Clear Color */}
          {selectedColor && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                onColorSelect(null);
                setIsOpen(false);
              }}
              className="w-full border-[var(--border)] text-[var(--muted-foreground)] hover:text-[var(--foreground)] hover:bg-[var(--gray-700)]"
            >
              {Icons.trash}
              <span className="ml-2">Clear Color</span>
            </Button>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}
