const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

// 실제 SDK 호출 없이 문서의 카메라·오버레이 연결 계약만 검사합니다.
function documentFixture() {
  const events = [], maps = [], overlays = [], lines = [];
  const element = () => ({listeners:{}, attributes:{}, style:{values:{},setProperty(name,value){this.values[name]=value;}}, addEventListener(name,handler){this.listeners[name]=handler;},setAttribute(name,value){this.attributes[name]=value;}});
  const container=element();
  class LatLng {constructor(lat,lng){this.lat=lat;this.lng=lng;} getLat(){return this.lat;} getLng(){return this.lng;}}
  class Bounds {constructor(){this.points=[];} extend(p){this.points.push(p);}}
  class MapView {
    constructor(_,options){this.center=options.center;this.level=options.level;this.listeners={};this.moves=0;maps.push(this);}
    setMinLevel(){} setMaxLevel(){} relayout(){}
    setCenter(value){this.center=value;this.moves++;} getCenter(){return this.center;}
    setLevel(value){this.level=value;} getLevel(){return this.level;}
    jump(center,level,options){this.center=center;this.level=level;this.animation=options;this.jumps=(this.jumps||0)+1;}
    setBounds(bounds,...padding){this.bounds=bounds;this.padding=padding;this.level=2;}
  }
  class Overlay {constructor(options){Object.assign(this,options);overlays.push(this);}setMap(value){this.map=value;}setPosition(value){this.position=value;}}
  class Line {constructor(options){Object.assign(this,options);lines.push(this);}setMap(value){this.map=value;}}
  const window={RunSpotMap:{postMessage:message=>events.push(JSON.parse(message))}};
  const kakao={maps:{Map:MapView,LatLng,LatLngBounds:Bounds,CustomOverlay:Overlay,Polyline:Line,load:fn=>fn(),event:{addListener(map,name,fn){map.listeners[name]=fn;}}}};
  window.kakao=kakao;
  const context={window,kakao,document:{getElementById:()=>container,createElement:element},ResizeObserver:class{observe(){}},Map,Set,JSON,Math};
  const html=fs.readFileSync('assets/maps/kakao_map.html','utf8');
  const inline=html.match(/<script>([\s\S]*?)<\/script>/)[1];
  vm.runInNewContext(inline,context);
  window.createRunspotMap();
  return {events,map:maps[0],overlays,lines,container,window,update:window.runspotMap.update,frame:window.runspotMap.auraFrame,effects:()=>Array.from(window.runspotMap.auraEffects())};
}
const data = () => ({camera:{type:'move',revision:0,center:[37,127],zoom:16.5},position:[37,127],markers:[],segments:[],endpoints:false});

test('러닝 배율과 지도 이동을 적용하고 같은 카메라 명령은 반복하지 않습니다',()=>{
  const f=documentFixture(),d=data();f.update(d);
  assert.equal(f.map.level,4);assert.equal(f.map.center.getLat(),37);
  const moves=f.map.moves;f.update(d);assert.equal(f.map.moves,moves);
  assert.equal(f.events[0].type,'ready');
  f.map.listeners.dragstart();assert.equal(f.events.at(-1).type,'gesture');
  f.map.listeners.idle();assert.equal(f.events.at(-1).type,'camera');
});
test('시작 확대는 700ms SDK 애니메이션으로 한 번만 실행합니다',()=>{
  const f=documentFixture(),d=data();d.camera.animate=true;f.update(d);
  assert.equal(f.map.level,4);assert.equal(f.map.animation.animate.duration,700);assert.equal(f.map.jumps,1);
  f.update({...d,position:[37.00001,127]});assert.equal(f.map.jumps,1);
  f.update({...d,camera:{...d.camera,revision:1,center:[37.00001,127],animate:false}});
  assert.equal(f.map.jumps,1);assert.equal(f.map.center.getLat(),37.00001);
});
test('단절된 경로를 각각 그리고 출발·도착을 따로 표시합니다',()=>{
  const f=documentFixture(),d=data();d.segments=[[[37,127],[37.1,127]],[[38,128],[38.1,128]]];d.endpoints=true;
  f.update(d);assert.equal(f.lines.length,4);assert.equal(f.lines[0].path.length,2);assert.equal(f.lines[2].path[0].getLat(),38);
  assert.deepEqual(f.overlays.filter(o=>o.content.className.startsWith('endpoint')).map(o=>o.content.attributes['aria-label']),['출발','도착']);
  for (const marker of f.overlays.filter(o=>o.content.className.startsWith('endpoint'))) {
    assert.equal(marker.content.textContent,undefined);
    assert.match(marker.content.innerHTML,/<svg /);
  }
  const lines=f.lines.length;f.update(d);assert.equal(f.lines.length,lines);
  f.update({...d,segments:[]});assert.ok(f.lines.every(l=>l.map===null));
});
test('이름은 텍스트로 표시하며 삭제된 러너·내 위치는 지도에서 제거합니다',()=>{
  const f=documentFixture(),d=data();d.markers=[{id:'friend',point:[37,127],nickname:'<img onerror=alert(1)>',selected:true}];f.update(d);
  const runner=f.overlays.find(o=>o.content.className==='runner selected');
  assert.equal(runner.content.title,d.markers[0].nickname);assert.equal(runner.content.innerHTML,undefined);
  runner.content.listeners.click({stopPropagation(){}});assert.equal(f.events.at(-1).id,'friend');
  f.update({...d,markers:[],position:null});assert.equal(runner.map,null);assert.ok(f.overlays.every(o=>o.map===null));
});
test('기록 전체 범위는 SDK 영역 맞춤과 최대 확대 수준을 사용합니다',()=>{
  const f=documentFixture(),d=data();d.camera={type:'fit',revision:1,points:[[37,127],[38,128]],maxZoom:17,padding:40};f.update(d);
  assert.equal(f.map.bounds.points.length,2);assert.deepEqual(f.map.padding,[40,40,40,40]);assert.equal(f.map.level,3);
});

test('그룹은 인원수를 표시하고 분리되면 그룹 아이콘을 제거합니다',()=>{
  const f=documentFixture(),d=data();
  d.markers=[{id:'group:a:b',point:[37,127],nickname:'함께 달리기 2명',memberCount:2}];
  f.update(d);
  const group=f.overlays.find(o=>o.content.className==='runner group');
  assert.equal(group.content.textContent,'2명');
  assert.equal(group.content.attributes['aria-label'],'함께 달리기 2명');
  group.content.listeners.click({stopPropagation(){}});
  assert.equal(f.events.at(-1).id,'group:a:b');
  f.update({...d,markers:[{id:'a',point:[37,127],nickname:'가나다'},{id:'b',point:[37.001,127],nickname:'라마바'}]});
  assert.equal(group.map,null);
  assert.equal(f.overlays.filter(o=>o.map&&o.content.className==='runner').length,2);
});
test('착용한 테두리를 고른 색으로 내 위치 원에 표시하고 해제하면 기본 원으로 돌아갑니다',()=>{
  const f=documentFixture(),d=data();f.update(d);
  const own=f.overlays.find(o=>o.content.attributes['aria-label']==='내 현재 위치').content;
  assert.equal(own.className,'point');
  f.update({...d,frame:{style:'aura',color:'#EF4444'}});
  assert.equal(own.className,'point frame aura');assert.match(own.innerHTML,/<svg /);
  assert.equal(own.style.values['--c'],'#EF4444');assert.equal(own.style.values['--g'],'#EF444499');
  f.update({...d,frame:{style:'basic',color:'#22C55E'}});
  assert.equal(own.className,'point frame basic');assert.equal(own.style.values['--c'],'#22C55E');
  // 형식이 잘못된 색은 그리지 않습니다.
  f.update({...d,frame:{style:'basic',color:'red;x'}});assert.equal(own.className,'point');
  f.update({...d,frame:null});assert.equal(own.className,'point');assert.equal(own.innerHTML,'');
});

// 오라 합체 테스트용 상태입니다. 거리 판정은 앱이 하므로 여기서는 받은 값만 씁니다.
const auraData = (links, nodes=[{id:'a',point:[37.0002,127],color:'#3182F6',crew:null,sync:true}], crew=null) => ({
  ...data(), frame:{style:'aura',color:'#EF4444'},
  markers: nodes.map(n => ({id:n.id,point:n.point,nickname:'친구'+n.id,selected:false,memberCount:1,frame:{style:'aura',color:n.color}})),
  aura:{self:{color:'#EF4444',crew,sync:true},nodes,links},
});
test('합쳐진 오라는 가운데에서 두 색이 반반 섞이고 가까운 쪽 색을 따릅니다',()=>{
  const f=documentFixture(),M=f.window.runspotAura;
  const red=M.rgb('#FF0000'),blue=M.rgb('#0000FF');
  const shapes=[{x:0,y:0,r:40,c:red},{x:60,y:0,r:40,c:blue},{link:true,ax:0,ay:0,bx:60,by:0,r:25,w:.9,ca:red,cb:blue}];
  const mid=M.sample(shapes,30,0,[0,0,0,0]);
  assert.ok(mid[0]>.5);assert.ok(Math.abs(mid[1]-mid[3])<1);assert.ok(mid[1]>200&&mid[2]<1);
  const left=M.sample(shapes,-10,0,[0,0,0,0]);assert.ok(left[1]>left[3]*5);
  // 서로 닿지 않는 거리에서는 이어 주는 목이 없으면 가운데가 비어 있습니다.
  assert.equal(M.sample([{x:0,y:0,r:40,c:red},{x:100,y:0,r:40,c:blue}],50,0,[0,0,0,0])[0],0);
  // 기본 기준(합체 300m·분리 400m·빛줄기 600m)과 앱이 보낸 기준을 모두 따릅니다.
  assert.equal(M.beam(600),0);assert.equal(M.beam(300),1);assert.ok(M.beam(400)>M.beam(550));
  assert.equal(M.neck(300),1);assert.ok(M.neck(400)<M.neck(350));
  const old={merge:25,split:40,beam:100};
  assert.equal(M.beam(100,old),0);assert.equal(M.neck(25,old),1);assert.ok(M.neck(40,old)<M.neck(30,old));
});
test('다른 러너의 테두리를 그 색으로 보여주고 오라가 이어지면 개별 오라를 끕니다',()=>{
  const f=documentFixture();
  const far={...auraData([]),aura:null};
  f.update(far);
  const own=f.overlays.find(o=>o.content.attributes['aria-label']==='내 현재 위치').content;
  const friend=f.overlays.find(o=>o.content.attributes['aria-label']==='친구a').content;
  assert.equal(friend.className,'runner framed aura');assert.equal(friend.style.values['--c'],'#3182F6');
  assert.equal(own.className,'point frame aura');
  f.update(auraData([{a:'self',b:'a',m:70,merged:false}]));
  assert.equal(own.className,'point frame aura fused');assert.equal(friend.className,'runner framed aura fused');
  assert.deepEqual(f.effects(),[]);
  f.update(far);
  assert.equal(own.className,'point frame aura');assert.equal(friend.className,'runner framed aura');
});
test('합쳐질 때 합류 연출을, 떨어질 때 분리 연출을 한 번씩 냅니다',()=>{
  const f=documentFixture();
  f.update(auraData([{a:'self',b:'a',m:60,merged:false}]));
  f.update(auraData([{a:'self',b:'a',m:24,merged:true}],undefined,0));
  assert.deepEqual(f.effects(),['join']);
  f.update(auraData([{a:'self',b:'a',m:30,merged:true}],undefined,0));
  assert.deepEqual(f.effects(),['join']);
  f.frame(1000);f.frame(2500);
  assert.deepEqual(f.effects(),[]);
  f.update(auraData([{a:'self',b:'a',m:45,merged:false}]));
  assert.deepEqual(f.effects(),['split']);
  f.frame(3000);f.frame(4500);
  assert.deepEqual(f.effects(),[]);
  // 합쳐진 채로 친구가 지도에서 사라져도 분리로 처리합니다.
  f.update(auraData([{a:'self',b:'a',m:20,merged:true}],undefined,0));
  f.update({...auraData([]),aura:null,markers:[]});
  assert.deepEqual(f.effects(),['join','split']);
});
test('오라가 이어진 친구 아이콘은 새 위치로 부드럽게 옮깁니다',()=>{
  const f=documentFixture();
  f.update(auraData([{a:'self',b:'a',m:60,merged:false}]));
  const marker=f.overlays.find(o=>o.content.attributes['aria-label']==='친구a');
  f.frame(1000);
  f.update(auraData([{a:'self',b:'a',m:60,merged:false}],[{id:'a',point:[37.0004,127],color:'#3182F6',crew:null,sync:true}]));
  f.frame(1100);
  const moved=marker.position.getLat();
  assert.ok(moved>37.0002&&moved<37.0004);
  for(let t=1200;t<9000;t+=100)f.frame(t);
  assert.ok(Math.abs(marker.position.getLat()-37.0004)<1e-6);
});
