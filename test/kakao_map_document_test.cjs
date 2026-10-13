const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

// 실제 SDK 호출 없이 문서의 카메라·오버레이 연결 계약만 검사합니다.
function documentFixture() {
  const events = [], maps = [], overlays = [], lines = [];
  const element = () => ({listeners:{}, attributes:{}, addEventListener(name,handler){this.listeners[name]=handler;},setAttribute(name,value){this.attributes[name]=value;}});
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
  const context={window,kakao,document:{getElementById:()=>container,createElement:element},ResizeObserver:class{observe(){}},Map,Set,JSON};
  const html=fs.readFileSync('assets/maps/kakao_map.html','utf8');
  const inline=html.match(/<script>([\s\S]*?)<\/script>/)[1];
  vm.runInNewContext(inline,context);
  window.createRunspotMap();
  return {events,map:maps[0],overlays,lines,container,update:window.runspotMap.update};
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
  assert.deepEqual(f.overlays.filter(o=>o.content.className.startsWith('endpoint')).map(o=>o.content.textContent),['출발','도착']);
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
