const {test}=require('node:test');
const assert=require('node:assert/strict');
const d=require('../lib/domain');
test('exact hostel inventory and floor distribution',()=>{
 assert.equal(d.buildings.length,5); assert.equal(d.machines.length,16); assert.equal(new Set(d.machines.map(x=>x.id)).size,16);
 assert.deepEqual(d.buildings.map(b=>d.machines.filter(m=>m.buildingId===b.id).length),[2,2,4,4,4]);
 for(const b of d.buildings) for(let floor=1;floor<=b.floors;floor++) assert.equal(d.machines.filter(m=>m.buildingId===b.id&&m.floorNumber===floor).length,b.perFloor);
 assert.deepEqual(d.equipment.map(x=>x.id),['DJ-TT1','KENNEDY-TT1','KENNEDY-CARROM1']);
});
test('all 28 translated meals exist without Malayalam; unresolved source is gated',()=>{
 const m=require('../../assets/menu/weekly-menu.json');
 assert.equal(Object.keys(m.days).length,7);
 for(const day of d.weekdays) { d.weeklyDay.parse(m.days[day]); assert.equal(Object.keys(m.days[day]).length,4); }
 if(m.verificationNotes.length) assert.equal(m.verified,false);
});
test('reminders have server scheduling intervals',()=>{assert.equal(d.reminderDelay('washing'),1200);assert.equal(d.reminderDelay('drying'),43200);});
test('invalid paths, dates and food text rejected',()=>{
 assert.equal(d.id.safeParse('../secret').success,false);
 assert.equal(d.date.safeParse('2026-02-30').success,false);
 assert.equal(d.items.safeParse([]).success,false);
 assert.equal(d.items.safeParse(['\u0d05']).success,false);
});
