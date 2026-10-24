const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'..');
const menu=require('../assets/menu/weekly-menu.json');
const labels={breakfast:'Breakfast',lunch:'Lunch',snacks:'Evening Snacks',dinner:'Dinner'};
let text='# MH MENU 25-26 — English weekly menu\n\nTranscribed from both supplied photographs. Slashes preserve printed alternatives.\n\n';
for(const [day,meals]of Object.entries(menu.days)){text+=`## ${day}\n\n`;for(const [meal,foods]of Object.entries(meals))text+=`- **${labels[meal]}:** ${foods.join('; ')}.\n`;text+='\n';}
text+='## Accepted interpretations\n\n'+menu.acceptedInterpretations.map(s=>'- '+s).join('\n')+'\n';
fs.writeFileSync(path.join(root,'docs/WEEKLY_MENU.md'),text);
console.log('Rendered all 28 meals to docs/WEEKLY_MENU.md');
