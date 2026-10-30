import {z} from 'zod';
export const buildings = [
  {id:'HS1', name:'HS1', floors:2, perFloor:1},
  {id:'HS2', name:'HS2', floors:2, perFloor:1},
  {id:'KENNEDY', name:'Kennedy', floors:2, perFloor:2},
  {id:'DJ', name:'DJ', floors:4, perFloor:1},
  {id:'MB', name:'MB', floors:3, perFloor:1},
];
export const machines = buildings.flatMap(b => Array.from({length:b.floors}, (_,f) =>
  Array.from({length:b.perFloor}, (_,m) => ({id:`${b.id}-F${f+1}-WM${m+1}`,buildingId:b.id,floorNumber:f+1,machineNumber:m+1}))).flat());
export const equipment = [
  {id:'DJ-TT1',buildingId:'DJ',equipmentType:'Table Tennis'},
  {id:'KENNEDY-TT1',buildingId:'KENNEDY',equipmentType:'Table Tennis'},
  {id:'KENNEDY-CARROM1',buildingId:'KENNEDY',equipmentType:'Carrom'},
];
export const id = z.string().regex(/^[a-zA-Z0-9_-]{1,128}$/);
export const kind = z.enum(['laundry','sports']);
export const meal = z.enum(['breakfast','lunch','snacks','dinner']);
export const english = z.string().trim().min(1).max(120).regex(/^[\x20-\x7E]+$/, 'Use English text');
export const items = z.array(english).min(1).max(20);
export const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(s => !Number.isNaN(Date.parse(s)) && new Date(s).toISOString().startsWith(s), 'Invalid date');
export const weeklyDay = z.object({breakfast:items,lunch:items,snacks:items,dinner:items}).strict();
export const weekdays = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
export const statusReasons = ['Machine is actually free','Machine is occupied but marked available','Machine is broken','Other problem'] as const;
export const chatReasons = ['Abusive language','Vulgar content','Harassment','Spam','Threats','Other'] as const;
export function reminderDelay(type:'washing'|'drying') { return type === 'washing' ? 20*60 : 12*60*60; }
export function normalizeMessage(text:string) { return text.toLowerCase().replace(/\s+/g,' ').trim(); }
