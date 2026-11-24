import assert from 'node:assert/strict';
import { readFile,writeFile,mkdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import pg from 'pg';
import { startNativePostgres } from './native-postgres.mjs';
import { DEPLOYMENT_SCHEMA_SQL } from '../deployment-readiness.mjs';
import { testConfiguredCatalog } from './configured-catalog-acceptance.mjs';
import { testCommercialSuite } from './commercial-suite-acceptance.mjs';
import { testCloudLogistics } from './cloud-logistics-acceptance.mjs';

const startedAt=Date.now();
const cluster=await startNativePostgres();
const db=cluster.client();const pool=new pg.Pool({...cluster.settings,max:24});
const results=[];
async function check(name,fn){const start=Date.now();await fn();results.push({name,status:'passed',durationMs:Date.now()-start});console.log(`PASS ${name}`);}
async function authenticatedQuery(user,sql,args=[]){
  const client=await pool.connect();
  try{
    await client.query('begin');await client.query('set local role authenticated');
    await client.query("select set_config('request.jwt.claim.sub',$1,true)",[user]);
    const response=await client.query(sql,args);
    await client.query('commit');return response;
  }catch(error){await client.query('rollback');throw error;}finally{client.release();}
}
const as=async(user,name,args=[])=>(await authenticatedQuery(user,`select public.${name}(${args.map((_,i)=>`$${i+1}`).join(',')}) data`,args)).rows[0].data;
const rpc=(id,action,payload={})=>as(id,'delivery_marketplace',[action,payload]);
try{
  await db.connect();
  await db.query(`create role authenticated;create role anon;create schema auth;create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;
    create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    grant usage on schema storage to authenticated;grant select,insert on storage.objects to authenticated;create publication supabase_realtime;`);
  await check('P0 latest additive migrations and catalog privacy',async()=>{
    for(const file of ['20261027_delivery_integrations','20261028_cloud_orders','20261029_payments_ghn','20261029_cloud_addresses',
      '20261030_marketplace','20261031_market_operations','20261101_partner_memberships','20261102_local_address_import','20261103_catalog_stock_versions','20261104_market_media','20261105_market_browse','20261106_catalog_configuration','20261107_cloud_commercial_suite','20261108_cloud_logistics','20261109_admin_account_management','20261110_cloud_promo_events','20261111_profile_push_shipping_coins','20261112_shipping_cash_settlement','20261113_cloud_sync_and_journey','20261114_merchant_cloud_suite','20261115_driver_wallet_and_showcase_catalog','20261116_realtime_dispatch_pricing_and_pod_signature','20261117_vehicle_classes_and_driver_applications']) {
      await db.query(await readFile(new URL(`../../../database/migrations/${file}.sql`,import.meta.url),'utf8'));
    }
    const schema=(await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
    for(const [key,value] of Object.entries(schema))assert.equal(value,true,`schema ${key}`);
  });
  const operator=randomUUID(),merchant=randomUUID(),driver=randomUUID(),secondDriver=randomUUID();
  const buyers=Array.from({length:8},()=>randomUUID());
  for(const id of [operator,merchant,driver,secondDriver,...buyers]){
    await db.query('insert into auth.users values($1)',[id]);
    await as(id,'delivery_cloud_profile',[{full_name:'Isolated PostgreSQL test',phone:'0901234567',requested_role:'customer'}]);
  }
  await db.query("insert into delivery_api_profiles values($1,'operator')",[operator]);
  for(const [id,role] of [[merchant,'merchant'],[driver,'driver'],[secondDriver,'driver']]){
    await as(id,'delivery_cloud_membership',[role,'request']);
    await as(operator,'delivery_cloud_membership',[role,'approve',id,1,'']);
  }
  const shop=(await rpc(merchant,'shop_save',{name:'Isolated stock shop',description:'',address:'12 Nguyen Hue TP HCM',latitude:10.77,longitude:106.7,paused:false})).shop;
  const product=(await rpc(merchant,'product_save',{id:randomUUID(),shop_id:shop.id,name:'Stock race item',description:'',category:'Food',sku:'RACE-1',price:50000,stock:2,weight_kg:1,published:true})).product;
  await rpc(operator,'shop_moderate',{id:shop.id,version:1,status:'active'});
  const quotes=[];
  for(const buyer of buyers){
    const address=(await as(buyer,'delivery_cloud_addresses_manage',[randomUUID(),{label:'Home',recipient_name:'Recipient',recipient_phone:'0912345678',
      full_address:'20 Le Loi TP HCM',latitude:10.78,longitude:106.71,is_default:true},false,null])).addresses[0];
    await rpc(buyer,'cart_set',{product_id:product.id,quantity:1,version:1});
    quotes.push((await rpc(buyer,'quote',{address_id:address.id})).quote);
  }
  let winner,order;
  await check('P1-P2 eight concurrent buyers cannot oversell two units',async()=>{
    const submitted=await Promise.allSettled(buyers.map((b,i)=>rpc(b,'checkout',{quote_id:quotes[i].id,request_key:randomUUID()})));
    const succeeded=submitted.filter(r=>r.status==='fulfilled'),rejected=submitted.filter(r=>r.status==='rejected');
    assert.equal(succeeded.length,2);assert.equal(rejected.length,6);
    assert.ok(rejected.every(r=>r.reason.code==='PT409'),rejected.map(r=>r.reason.code).join(','));
    assert.equal((await db.query('select stock from delivery_market_products where id=$1',[product.id])).rows[0].stock,0);
    assert.equal((await db.query('select count(*)::int n from delivery_market_purchases')).rows[0].n,2);
    winner=buyers[submitted.findIndex(r=>r.status==='fulfilled')];
    order=(await rpc(winner,'orders')).orders[0];
  });
  await check('P2 parallel checkout replay returns one purchase and one stock allocation',async()=>{
    const quote=quotes[buyers.indexOf(winner)],key=randomUUID();
    const replay=await Promise.all(Array.from({length:6},()=>rpc(winner,'checkout',{quote_id:quote.id,request_key:key})));
    assert.equal(new Set(replay.map(r=>r.purchase.id)).size,1);
    assert.equal((await db.query("select count(*)::int n from delivery_market_stock where reason='purchase_allocate'")).rows[0].n,2);
  });
  await check('P1-P2 price changes and hidden products invalidate quotes without allocating stock',async()=>{
    const buyer=buyers[7];
    const address=(await as(buyer,'delivery_cloud_addresses_manage')).addresses[0];
    await db.query('update delivery_market_products set stock=10,version=version+1 where id=$1',[product.id]);
    const quote=(await rpc(buyer,'quote',{address_id:address.id})).quote;
    await db.query('update delivery_market_products set price=price+1000,version=version+1 where id=$1',[product.id]);
    await assert.rejects(rpc(buyer,'checkout',{quote_id:quote.id,request_key:randomUUID()}),e=>e.code==='PT409');
    const next=(await rpc(buyer,'quote',{address_id:address.id})).quote;
    await db.query('update delivery_market_products set published=false,version=version+1 where id=$1',[product.id]);
    await assert.rejects(rpc(buyer,'checkout',{quote_id:next.id,request_key:randomUUID()}),e=>e.code==='PT409');
    const state=(await db.query('select stock,terms_version from delivery_market_products where id=$1',[product.id])).rows[0];
    assert.equal(state.stock,10);assert.equal(state.terms_version,3);
    assert.equal((await db.query('select count(*)::int n from delivery_market_purchases')).rows[0].n,2);
  });
  await check('P1 reserved product media enforces real Storage RLS, ownership, blocking and immutable writes',async()=>{
    const hash='b'.repeat(64);
    const reserved=await as(merchant,'delivery_market_media_reserve',[shop.id,hash,200]);
    assert.equal((await as(merchant,'delivery_market_media_reserve',[shop.id,hash,200])).name,reserved.name);
    await assert.rejects(as(merchant,'delivery_market_media_reserve',[shop.id,hash,201]),e=>e.code==='PT409');
    await assert.rejects(as(buyers[0],'delivery_market_media_reserve',[shop.id,hash,200]),e=>e.code==='PT403');
    await assert.rejects(authenticatedQuery(merchant,'select * from delivery_market_media'),e=>e.code==='42501');
    await assert.rejects(authenticatedQuery(buyers[0],'insert into storage.objects(bucket_id,name) values($1,$2)',[reserved.bucket,reserved.name]),e=>e.code==='42501');
    await assert.rejects(authenticatedQuery(merchant,'insert into storage.objects(bucket_id,name) values($1,$2)',[reserved.bucket,reserved.name+'forged']),e=>e.code==='42501');
    await authenticatedQuery(merchant,'insert into storage.objects(bucket_id,name) values($1,$2)',[reserved.bucket,reserved.name]);
    await assert.rejects(authenticatedQuery(merchant,'update storage.objects set name=$1 where name=$2',['changed',reserved.name]),e=>e.code==='42501');
    await db.query('update delivery_cloud_accounts set blocked=true where user_id=$1',[merchant]);
    assert.equal(await as(merchant,'delivery_market_media_can_upload',[reserved.name]),false);
    await assert.rejects(as(merchant,'delivery_market_media_reserve',[shop.id,'c'.repeat(64),200]),e=>e.code==='PT403');
    await db.query('update delivery_cloud_accounts set blocked=false where user_id=$1',[merchant]);
  });
  await check('P1-P2 server filters, tied-price pagination and public shop projection',async()=>{
    for(let i=0;i<55;i++)await rpc(merchant,'product_save',{id:randomUUID(),shop_id:shop.id,name:`Browse ${i}`,description:'',
      category:i%2?'A':'B',sku:`BROWSE-${i}`,price:1000+(i%3)*1000,stock:i%4===0?0:1,weight_kg:1,published:true});
    const browse=d=>as(buyers[0],'delivery_market_browse',[d]);
    const first=await browse({sort:'price_asc'}),second=await browse({sort:'price_asc',...first.next});
    const all=[...first.products,...second.products];
    assert.equal(first.products.length,50);assert.equal(second.products.length,5);assert.equal(second.next,null);
    assert.equal(new Set(all.map(p=>p.id)).size,55);
    assert.deepEqual(all.map(p=>p.price),all.map(p=>p.price).sort((a,b)=>a-b));
    assert.ok(all.every(p=>!('sort_value' in p)));assert.deepEqual(first.categories,['A','B']);
    const filtered=await browse({shop_id:shop.id,category:'A',min_price:2000,max_price:3000,in_stock:true,sort:'price_desc'});
    assert.ok(filtered.products.length>0);assert.ok(filtered.products.every(p=>p.category==='A'&&p.stock>0&&p.price>=2000&&p.price<=3000));
    assert.deepEqual(Object.keys(filtered.shop).sort(),['address','description','id','name','open','opening_schedule','paused']);
    for(const d of [{min_price:-1},{max_price:1.5},{min_price:3000,max_price:1000},{in_stock:'true'},{sort:'random'},{after:randomUUID()},{owner_id:merchant}]){
      await assert.rejects(browse(d),e=>e.code==='PT400');
    }
    await assert.rejects(authenticatedQuery(buyers[0],"set local role anon; select public.delivery_market_browse('{}')"),e=>e.code==='42501');
    await db.query('update delivery_market_shops set paused=true where id=$1',[shop.id]);
    const paused=await browse({shop_id:shop.id});assert.equal(paused.products.length,0);assert.equal(paused.shop.paused,true);
    await db.query('update delivery_market_shops set paused=false where id=$1',[shop.id]);
  });
  await check('P0 partner revoke racing a new trip never strands an unauthorized assignment',async()=>{
    let ready=(await rpc(merchant,'order_action',{order_id:order.id,version:order.version,action:'accept'})).order;
    ready=(await rpc(merchant,'order_action',{order_id:order.id,version:ready.version,action:'ready'})).order;
    order=ready;
    const shipping=(await as(winner,'delivery_cloud_list')).orders.find(o=>o.id===ready.delivery_id);
    const raced=await Promise.allSettled([
      as(driver,'delivery_cloud_transition',[shipping.id,'claim',shipping.version,randomUUID(),'']),
      as(operator,'delivery_cloud_membership',['driver','revoke',driver,2,'Operational review']),
    ]);
    assert.equal(raced.filter(r=>r.status==='fulfilled').length,1);
    assert.ok(raced.filter(r=>r.status==='rejected').every(r=>['PT409','PT404'].includes(r.reason.code)));
    const assigned=(await db.query('select driver_id from delivery_cloud_orders where id=$1',[shipping.id])).rows[0].driver_id;
    const active=(await db.query("select state='active' as active from delivery_cloud_memberships where user_id=$1 and role='driver'",[driver])).rows[0].active;
    if(assigned)assert.equal(active,true);else assert.equal(active,false);
  });
  await check('P4 competing drivers commit exactly one claim',async()=>{
    let shipping=(await as(winner,'delivery_cloud_list')).orders.find(o=>o.id===order.delivery_id);
    if(shipping.driver_id){
      for(const action of ['arrive','pickup','deliver']) {
        shipping=await as(driver,'delivery_cloud_transition',[shipping.id,action,shipping.version,randomUUID(),'']);
      }
    }
    const state=(await as(driver,'delivery_cloud_profile')).account.memberships.find(m=>m.role==='driver');
    if(state.state!=='active'){
      await as(driver,'delivery_cloud_membership',['driver','request']);
      const pending=(await as(driver,'delivery_cloud_profile')).account.memberships.find(m=>m.role==='driver');
      await as(operator,'delivery_cloud_membership',['driver','approve',driver,pending.version,'']);
    }
    // Use a fresh isolated shipment instead of resetting a committed status.
    const details={pickup_address:'12 Nguyen Hue',dropoff_address:'20 Le Loi',recipient_name:'Recipient',recipient_phone:'0912345678',package_description:'Claim race',
      pickup_lat:10.77,pickup_lng:106.7,dropoff_lat:10.78,dropoff_lng:106.71,weight_kg:1,cod_amount:0,service_type:'standard',payment_method:'recipient_cash'};
    const quote=await as(winner,'delivery_cloud_quote',[details]);
    const fresh=await as(winner,'delivery_cloud_create',[details,randomUUID(),quote.pricing_version,quote.shipping_fee]);
    const claims=await Promise.allSettled([driver,secondDriver].map(id=>as(id,'delivery_cloud_transition',[fresh.id,'claim',fresh.version,randomUUID(),''])));
    assert.equal(claims.filter(r=>r.status==='fulfilled').length,1);
    assert.ok(claims.filter(r=>r.status==='rejected').every(r=>['PT409','PT404'].includes(r.reason.code)));
  });
  await check('P0 concurrent address imports deduplicate without cross-account ownership',async()=>{
    const payload=[{source_key:'a'.repeat(64),details:{label:'Imported',recipient_name:'Recipient',recipient_phone:'0912345678',full_address:'99 Le Loi TP HCM',latitude:10.78,longitude:106.71}}];
    const imported=await Promise.all(Array.from({length:4},()=>as(buyers[7],'delivery_cloud_import',['commit',JSON.stringify(payload)])));
    assert.equal(imported.reduce((sum,r)=>sum+r.ready,0),1);
    const owner=(await db.query('select user_id from delivery_cloud_imports where source_key=$1',['a'.repeat(64)])).rows;
    assert.equal(owner.length,1);assert.equal(owner[0].user_id,buyers[7]);
  });
  await testConfiguredCatalog({db,as,rpc,operator,merchant,buyer:buyers[7],shop,check});
  await testCommercialSuite({db,as,rpc,operator,merchant,driver,secondDriver,buyers,shop,check,authenticatedQuery});
  await testCloudLogistics({db,as,operator,merchant,driver,buyers,check});
  await check('P7 cloud preferences, AI history, enriched queue privacy, live GPS/chat/checkpoints and driver reviews',async()=>{
    for(const file of ['20261109_admin_account_management','20261110_cloud_promo_events','20261111_profile_push_shipping_coins','20261112_shipping_cash_settlement','20261113_cloud_sync_and_journey','20261114_merchant_cloud_suite','20261115_driver_wallet_and_showcase_catalog','20261116_realtime_dispatch_pricing_and_pod_signature','20261117_vehicle_classes_and_driver_applications']) {
      await db.query(await readFile(new URL(`../../../database/migrations/${file}.sql`,import.meta.url),'utf8'));
    }
    const schemaAfterReapply=(await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
    for(const [key,value] of Object.entries(schemaAfterReapply))assert.equal(value,true,`reapplied schema ${key}`);
    const customer=buyers[0],journeyDriver=randomUUID();
    await db.query('insert into auth.users values($1)',[journeyDriver]);
    await as(journeyDriver,'delivery_cloud_profile',[{full_name:'Tai Xe Hanh Trinh',phone:'0908887776',requested_role:'customer'}]);
    await as(journeyDriver,'delivery_cloud_membership',['driver','request']);
    await as(operator,'delivery_cloud_membership',['driver','approve',journeyDriver,1,'']);
    const savedUi=await as(customer,'delivery_cloud_preferences',['save_ui',{theme_mode:'dark',preferred_role:'customer'}]);
    assert.deepEqual(savedUi.ui_preferences,{theme_mode:'dark',preferred_role:'customer'});
    await as(customer,'delivery_cloud_preferences',['save_draft',{draft:{pickup_address:'12 Nguyen Hue, Ben Nghe, Quan 1, TP HCM',dropoff_address:'20 Le Loi, Ben Thanh, Quan 1, TP HCM',service_type:'express'}}]);
    const prof=await as(customer,'delivery_cloud_profile');
    assert.equal(prof.account.ui_preferences.theme_mode,'dark');
    assert.equal(prof.account.shipping_draft.service_type,'express');
    const adminAcc=(await as(operator,'delivery_cloud_accounts_manage')).accounts.find(a=>a.user_id===customer);
    assert.equal(adminAcc.shipping_draft,undefined);

    await as(customer,'delivery_cloud_ai_history',['append_exchange',{user_text:'Tra cuu don hang',assistant_text:'Ban co the xem muc Don hang.'}]);
    const aiHist=await as(customer,'delivery_cloud_ai_history',['list',{}]);
    assert.equal(aiHist.messages.length,2);
    assert.equal(aiHist.messages[0].role,'user');
    assert.equal(aiHist.messages[1].role,'assistant');
    await as(customer,'delivery_cloud_ai_history',['clear',{}]);
    assert.equal((await as(customer,'delivery_cloud_ai_history',['list',{}])).messages.length,0);

    const tripDetails={
      pickup_address:'12 Nguyen Hue, Phuong Ben Nghe, Quan 1, TP HCM',
      dropoff_address:'20 Le Loi, Phuong Ben Thanh, Quan 1, TP HCM',
      recipient_name:'Khach Hang A',
      recipient_phone:'0912345678',
      package_description:'Tai lieu khan',
      pickup_lat:10.77312,pickup_lng:106.70425,
      dropoff_lat:10.77195,dropoff_lng:106.69831,
      extra_stops:[{address:'45 Ham Nghi, Quan 1, TP HCM',lat:10.7708,lng:106.7019,contact_name:'Diem dung 1',contact_phone:'0909111222'}],
      is_round_trip:true,
      prefer_ev:true,
      require_pod:false,
      require_otp:false,
      weight_kg:2,cod_amount:50000,service_type:'express',payment_method:'recipient_cash',
    };
    const tripQuote=await as(customer,'delivery_cloud_quote',[tripDetails]);
    const created=await as(customer,'delivery_cloud_create',[tripDetails,randomUUID(),tripQuote.pricing_version,tripQuote.shipping_fee]);
    assert.equal((await as(customer,'delivery_cloud_preferences',['get',{}])).shipping_draft,null);

    const queue=(await as(journeyDriver,'delivery_cloud_list',[true,null,null])).orders;
    const queued=queue.find(o=>o.id===created.id);
    assert.ok(queued);
    assert.equal(JSON.stringify(queued).includes('0912345678'),false);
    assert.equal(JSON.stringify(queued).includes('Nguyen Hue'),false);
    assert.equal(queued.details.pickup_area,'Quan 1, TP HCM');
    assert.equal(queued.details.stops_count,1);
    assert.equal(queued.details.is_round_trip,true);
    assert.equal(queued.details.prefer_ev,true);

    let claimed=await as(journeyDriver,'delivery_cloud_transition',[created.id,'claim',created.version,randomUUID(),'']);
    claimed=await as(journeyDriver,'delivery_cloud_transition',[created.id,'arrive',claimed.version,randomUUID(),'']);
    claimed=await as(journeyDriver,'delivery_cloud_transition',[created.id,'pickup',claimed.version,randomUUID(),'']);

    const t0=Date.now();
    const gpsOk=await as(journeyDriver,'delivery_cloud_order_live',['push_gps',{order_id:created.id,latitude:10.77312,longitude:106.70425,heading:180,speed_kmh:32,timestamp_ms:t0}]);
    assert.equal(gpsOk.ok,true);
    await assert.rejects(
      as(journeyDriver,'delivery_cloud_order_live',['push_gps',{order_id:created.id,latitude:10.95,longitude:106.95,timestamp_ms:t0+1000}]),
      e=>e.code==='PT409'
    );
    await as(customer,'delivery_cloud_order_live',['send_chat',{order_id:created.id,text:'Goi cho minh khi toi cong nhe'}]);
    await as(journeyDriver,'delivery_cloud_order_live',['send_chat',{order_id:created.id,text:'Da nhan thong tin, minh dang di'}]);
    const cp=await as(journeyDriver,'delivery_cloud_order_live',['mark_checkpoint',{order_id:created.id,checkpoint_key:'stop:0',note:'Da giao diem dung 1'}]);
    assert.equal(cp.order.completed_checkpoints.length,1);

    const snap=await as(customer,'delivery_cloud_order_live',['snapshot',{order_id:created.id}]);
    assert.equal(snap.messages.length,2);
    assert.equal(snap.gps_trail.length,1);
    assert.equal(snap.order.driver_profile.user_id,journeyDriver);
    assert.equal(snap.order.sender_profile.phone,'0901234567');

    let done=await as(journeyDriver,'delivery_cloud_transition',[created.id,'collect_cash',cp.order.version,randomUUID(),'']);
    done=await as(journeyDriver,'delivery_cloud_transition',[created.id,'deliver',done.version,randomUUID(),'Da giao tan tay']);
    const revRes=await as(customer,'delivery_market_operations',['partner_review_save',{target_kind:'driver',cloud_order_id:done.id,rating:5,body:'Tai xe giao cuc nhanh va lich su'}]);
    assert.equal(revRes.partner_review.rating,5);
    const driverRevs=await as(journeyDriver,'delivery_cloud_logistics',['driver_reviews',{}]);
    assert.ok(driverRevs.rating_count>=1);
    assert.ok(driverRevs.reviews.some(r=>r.id===revRes.partner_review.id));
    await as(journeyDriver,'delivery_market_operations',['review_reply',{review_kind:'partner',id:revRes.partner_review.id,reply:'Cam on anh chi rat nhieu!'}]);
    const finalOrder=(await as(customer,'delivery_cloud_list',[false,null,null])).orders.find(o=>o.id===done.id);
    assert.equal(finalOrder.driver_review.rating,5);
    assert.equal(finalOrder.driver_review.reply,'Cam on anh chi rat nhieu!');
  });
  await check('P8 merchant cloud suite RBAC, quick storefront/catalog controls, stock ledger, promotions, settlement math and delegated staff live journey',async()=>{
    const managerUser=randomUUID(),staffUser=randomUUID(),outsiderUser=randomUUID(),suiteDriver=randomUUID(),suiteBuyer=randomUUID();
    for(const [uid,name,phone] of [
      [managerUser,'Quan Ly Shop','0931112233'],
      [staffUser,'Nhan Vien Shop','0934445566'],
      [outsiderUser,'Nguoi Ngoai','0937778899'],
      [suiteDriver,'Tai Xe Suite','0939998877'],
      [suiteBuyer,'Nguoi Mua Suite','0912345678'],
    ]){
      await db.query('insert into auth.users values($1)',[uid]);
      await as(uid,'delivery_cloud_profile',[{full_name:name,phone,requested_role:'customer'}]);
    }
    await as(suiteBuyer,'delivery_cloud_addresses_manage',[randomUUID(),{
      label:'Nha Rieng',recipient_name:'Nguoi Mua Suite',recipient_phone:'0912345678',
      full_address:'20 Le Loi TP HCM',latitude:10.78,longitude:106.71,is_default:true,
    },false,null]);
    await as(suiteDriver,'delivery_cloud_membership',['driver','request']);
    await as(operator,'delivery_cloud_membership',['driver','approve',suiteDriver,1,'']);

    await rpc(merchant,'staff_save',{shop_id:shop.id,phone:'0931112233',role:'manager',active:true});
    await rpc(merchant,'staff_save',{shop_id:shop.id,phone:'0934445566',role:'staff',active:true});

    await assert.rejects(as(outsiderUser,'delivery_merchant_suite',['dashboard',{}]),e=>e.code==='PT403');
    const ownerDash=await as(merchant,'delivery_merchant_suite',['dashboard',{shop_id:shop.id}]);
    assert.equal(ownerDash.my_role,'owner');
    assert.ok(ownerDash.kpis.finance!==null);
    const managerDash=await as(managerUser,'delivery_merchant_suite',['dashboard',{shop_id:shop.id}]);
    assert.equal(managerDash.my_role,'manager');
    assert.ok(managerDash.kpis.finance!==null);
    const staffDash=await as(staffUser,'delivery_merchant_suite',['dashboard',{shop_id:shop.id}]);
    assert.equal(staffDash.my_role,'staff');
    assert.equal(staffDash.kpis.finance,null);

    await assert.rejects(
      as(staffUser,'delivery_merchant_suite',['shop_quick_pause',{shop_id:shop.id,paused:true,version:ownerDash.shops[0].version}]),
      e=>e.code==='PT403'
    );
    const pausedShop=(await as(managerUser,'delivery_merchant_suite',['shop_quick_pause',{shop_id:shop.id,paused:true,version:ownerDash.shops[0].version}])).shop;
    assert.equal(pausedShop.paused,true);
    assert.equal(pausedShop.status,'active');
    const resumedShop=(await as(managerUser,'delivery_merchant_suite',['shop_quick_pause',{shop_id:shop.id,paused:false,version:pausedShop.version}])).shop;
    assert.equal(resumedShop.paused,false);
    assert.equal(resumedShop.status,'active');

    const suiteProd=(await rpc(managerUser,'product_save',{
      id:randomUUID(),shop_id:shop.id,name:'Ca Phe Hat Rang Moc',description:'100% Arabica',
      category:'Do uong',sku:'CF-SUITE-1',price:120000,stock:5,weight_kg:0.5,published:true,
    })).product;
    await assert.rejects(
      as(staffUser,'delivery_merchant_suite',['product_quick_update',{product_id:suiteProd.id,version:suiteProd.version,stock:20}]),
      e=>e.code==='PT403'
    );
    const updatedProd=(await as(managerUser,'delivery_merchant_suite',['product_quick_update',{product_id:suiteProd.id,version:suiteProd.version,stock:18,published:true}])).product;
    assert.equal(updatedProd.stock,18);
    const stockLedger=await as(managerUser,'delivery_merchant_suite',['stock_ledger',{shop_id:shop.id,product_id:suiteProd.id}]);
    assert.ok(stockLedger.entries.some(e=>e.reason==='merchant_quick_adjust' && e.delta===13));
    await assert.rejects(as(staffUser,'delivery_merchant_suite',['stock_ledger',{shop_id:shop.id}]),e=>e.code==='PT403');

    const starts=new Date(Date.now()-60_000).toISOString();
    const ends=new Date(Date.now()+86_400_000).toISOString();
    const shopVoucher=(await rpc(managerUser,'voucher_save',{
      shop_id:shop.id,code:'MERCHSUITE10',title:'Giam 10k tai shop',discount_kind:'fixed',
      discount_value:10000,max_discount:10000,min_subtotal:50000,budget_total:500000,per_user_limit:2,
      starts_at:starts,ends_at:ends,active:true,
    })).voucher;
    await db.query(
      `insert into delivery_market_vouchers(id,code,shop_id,owner_user_id,title,discount_kind,discount_value,max_discount,min_subtotal,budget_total,per_user_limit,starts_at,ends_at,active,created_by)
       values($1,'PERSONALONLY',$2,$3,'Voucher ca nhan','fixed',5000,5000,0,5000,1,$4,$5,true,$3)`,
      [randomUUID(),shop.id,suiteBuyer,starts,ends]
    );
    const shopFlash=(await rpc(managerUser,'flash_sale_save',{
      product_id:suiteProd.id,sale_price:99000,allocated_stock:5,per_user_limit:2,starts_at:starts,ends_at:ends,active:true,
    })).flash_sale;
    const promos=await as(managerUser,'delivery_merchant_suite',['promotions',{shop_id:shop.id}]);
    assert.ok(promos.vouchers.some(v=>v.id===shopVoucher.id));
    assert.equal(promos.vouchers.some(v=>v.code==='PERSONALONLY'),false);
    assert.ok(promos.flash_sales.some(f=>f.id===shopFlash.id && f.product_name==='Ca Phe Hat Rang Moc'));

    const cartSnap=await rpc(suiteBuyer,'cart');
    await rpc(suiteBuyer,'cart_set',{product_id:suiteProd.id,quantity:1,version:cartSnap.version});
    const addrList=(await as(suiteBuyer,'delivery_cloud_addresses_manage')).addresses;
    const suiteQuote=(await rpc(suiteBuyer,'quote',{address_id:addrList[0].id})).quote;
    const suiteCheckout=await rpc(suiteBuyer,'checkout',{quote_id:suiteQuote.id,request_key:randomUUID()});
    assert.ok(suiteCheckout.purchase.id);

    const staffOrders=await as(staffUser,'delivery_merchant_suite',['orders_list',{shop_id:shop.id,filter:'pending'}]);
    const queuedOrder=staffOrders.orders.find(o=>o.purchase_id===suiteCheckout.purchase.id);
    assert.ok(queuedOrder);
    const suiteOrderId=queuedOrder.id;
    assert.equal(queuedOrder.buyer_profile.phone,'0912345678');

    const acceptedOrder=(await rpc(staffUser,'order_action',{order_id:suiteOrderId,action:'accept',version:queuedOrder.version})).order;
    const readyOrder=(await rpc(staffUser,'order_action',{order_id:suiteOrderId,action:'ready',version:acceptedOrder.version})).order;
    assert.ok(readyOrder.delivery_id);

    const staffLiveSnap=await as(staffUser,'delivery_cloud_order_live',['snapshot',{order_id:readyOrder.delivery_id}]);
    assert.equal(staffLiveSnap.order.id,readyOrder.delivery_id);
    const staffHist=await as(staffUser,'delivery_cloud_history_read',[readyOrder.delivery_id]);
    assert.ok(staffHist.history.length>=1);
    const staffMsg=await as(staffUser,'delivery_cloud_order_live',['send_chat',{order_id:readyOrder.delivery_id,text:'Shop da dong goi xong kien hang'}]);
    assert.equal(staffMsg.message.sender_role,'merchant');
    await assert.rejects(
      as(staffUser,'delivery_cloud_order_live',['push_gps',{order_id:readyOrder.delivery_id,latitude:10.77,longitude:106.7}]),
      e=>e.code==='PT403'
    );

    let deliv=await as(suiteDriver,'delivery_cloud_transition',[readyOrder.delivery_id,'claim',1,randomUUID(),'']);
    deliv=await as(suiteDriver,'delivery_cloud_transition',[deliv.id,'arrive',deliv.version,randomUUID(),'']);
    deliv=await as(suiteDriver,'delivery_cloud_transition',[deliv.id,'pickup',deliv.version,randomUUID(),'']);
    deliv=await as(suiteDriver,'delivery_cloud_transition',[deliv.id,'collect_cash',deliv.version,randomUUID(),'']);
    deliv=await as(suiteDriver,'delivery_cloud_transition',[deliv.id,'deliver',deliv.version,randomUUID(),'Giao thanh cong']);

    await as(suiteBuyer,'delivery_market_operations',['review_save',{order_id:suiteOrderId,product_id:suiteProd.id,rating:5,body:'Hat thom va dong goi ky'}]);
    const staffReviews=await as(staffUser,'delivery_merchant_suite',['aftersales_inbox',{shop_id:shop.id,tab:'reviews',filter:'unreplied'}]);
    const prodRev=staffReviews.reviews.find(r=>r.product_id===suiteProd.id);
    assert.ok(prodRev);
    await as(staffUser,'delivery_market_operations',['review_reply',{review_kind:'product',id:prodRev.id,reply:'Cam on quy khach da ung ho shop!'}]);
    await assert.rejects(
      as(staffUser,'delivery_merchant_suite',['aftersales_inbox',{shop_id:shop.id,tab:'finance'}]),
      e=>e.code==='PT403'
    );

    const dueAmount=Number(readyOrder.snapshot.payable_subtotal??readyOrder.snapshot.subtotal)+Number(readyOrder.snapshot.shipping_fee);
    const colReq=(await as(suiteDriver,'delivery_market_operations',['finance_request',{
      order_id:suiteOrderId,kind:'collection',amount:dueAmount,reason:'Nop COD du',evidence:'COD-SUITE-1',request_key:randomUUID(),
    }])).finance;
    await as(operator,'delivery_market_operations',['finance_action',{id:colReq.id,action:'approve',version:colReq.version,reason:'Duyet thu COD'}]);
    await as(operator,'delivery_market_operations',['finance_action',{id:colReq.id,action:'complete',version:colReq.version+1,evidence:'BANK-COD-1'}]);
    await db.query("update delivery_market_shop_orders set delivered_at=now()-interval '8 days' where id=$1",[suiteOrderId]);

    const settleDash=await as(managerUser,'delivery_merchant_suite',['dashboard',{shop_id:shop.id}]);
    const eligibleRow=settleDash.kpis.finance.eligible_orders.find(e=>e.order_id===suiteOrderId);
    assert.ok(eligibleRow && eligibleRow.eligible_amount>0);
    const settleReq=(await as(managerUser,'delivery_market_operations',['finance_request',{
      order_id:suiteOrderId,kind:'settlement',amount:eligibleRow.eligible_amount,reason:'De nghi quyet toan ky nay',evidence:'SETTLE-SUITE-1',request_key:randomUUID(),
    }])).finance;
    assert.equal(settleReq.amount,eligibleRow.eligible_amount);
    const financeInbox=await as(managerUser,'delivery_merchant_suite',['aftersales_inbox',{shop_id:shop.id,tab:'finance',filter:'settlement'}]);
    assert.ok(financeInbox.finance.some(f=>f.id===settleReq.id));
  });
  await check('P9 driver wallet 80/20 settlement, VietQR topup, bank withdrawal locking & virtual showcase catalog auto-dispatch',async()=>{
    const walletDriver=randomUUID(),foodBuyer=randomUUID();
    for(const [uid,name,phone] of [
      [walletDriver,'Tai Xe Vi Cloud','0941112233'],
      [foodBuyer,'Khach An Uong','0942223344'],
    ]){
      await db.query('insert into auth.users values($1)',[uid]);
      await as(uid,'delivery_cloud_profile',[{full_name:name,phone,requested_role:'customer'}]);
    }
    const buyerAddr=(await as(foodBuyer,'delivery_cloud_addresses_manage',[randomUUID(),{
      label:'Van Phong Q1',recipient_name:'Khach An Uong',recipient_phone:'0942223344',
      full_address:'68 Nguyen Hue, Quan 1, TP HCM',latitude:10.7745,longitude:106.7038,is_default:true,
    },false,null])).addresses[0];
    await as(walletDriver,'delivery_cloud_membership',['driver','request']);
    await as(operator,'delivery_cloud_membership',['driver','approve',walletDriver,1,'']);

    // 1. Clean start: 0 showcase shops before explicit seed; non-operator rejected
    const initialShowcase=await as(operator,'delivery_showcase_catalog',['status',{}]);
    assert.equal(initialShowcase.seeded,false);
    assert.equal(initialShowcase.shops_total,0);
    await assert.rejects(as(foodBuyer,'delivery_showcase_catalog',['seed',{}]),e=>e.code==='PT403');

    // 2. Operator seeds 6 virtual restaurants/beverage bars/stores (idempotent on re-run)
    const seeded=await as(operator,'delivery_showcase_catalog',['seed',{}]);
    assert.equal(seeded.seeded,true);
    assert.equal(seeded.shops_total,6);
    assert.equal(seeded.shops_active,6);
    assert.equal(seeded.products_total,25);
    assert.equal(seeded.variants_total,18);
    assert.ok(seeded.flash_sales_active>=3);
    const reseeded=await as(operator,'delivery_showcase_catalog',['seed',{}]);
    assert.equal(reseeded.shops_total,6);
    assert.equal(reseeded.products_total,25);

    // 3. Browse returns featured showcase shops strip + exact 7-key shop projection when filtered
    const marketHome=await as(foodBuyer,'delivery_market_browse',[{}]);
    assert.ok(Array.isArray(marketHome.shops) && marketHome.shops.length>=6);
    const teaShop=seeded.shops.find(s=>s.showcase_slug==='gong-tea-coffee-bar');
    assert.ok(teaShop);
    const teaBrowse=await as(foodBuyer,'delivery_market_browse',[{shop_id:teaShop.id}]);
    assert.deepEqual(Object.keys(teaBrowse.shop).sort(),['address','description','id','name','open','opening_schedule','paused']);
    assert.equal(teaBrowse.shop_meta.is_showcase,true);
    assert.ok(teaBrowse.products.length>=4);

    // 4. Buyer orders beverage with variant & sugar/ice/topping options -> auto-dispatches ready shipment!
    const milkTea=teaBrowse.products.find(p=>p.sku==='TS-TRAN-CHAU-01');
    assert.ok(milkTea && milkTea.variants_count>=2);
    const milkTeaDetail=await as(foodBuyer,'delivery_market_operations',['product_details',{product_id:milkTea.id}]);
    const sizeL=milkTeaDetail.variants.find(v=>v.sku==='TS-TC-SIZE-L');
    const cart0=await rpc(foodBuyer,'cart');
    await rpc(foodBuyer,'cart_set',{
      product_id:milkTea.id,
      variant_id:sizeL.id,
      quantity:2,
      version:cart0.version,
      selected_options:[{group_id:'muc_duong',option_id:'d50'},{group_id:'muc_da',option_id:'it_da'},{group_id:'topping_ts',option_id:'tc_den'},{group_id:'topping_ts',option_id:'kem_cheese'}],
    });
    const foodQuote=(await rpc(foodBuyer,'quote',{address_id:buyerAddr.id,voucher_code:'TRASUA15K'})).quote;
    assert.ok(foodQuote.snapshot.voucher_discount>0);
    const foodCheckout=await rpc(foodBuyer,'checkout',{quote_id:foodQuote.id,request_key:randomUUID()});
    const buyerOrders=(await rpc(foodBuyer,'orders')).orders;
    const teaOrder=buyerOrders.find(o=>o.purchase_id===foodCheckout.purchase.id);
    assert.ok(teaOrder);
    assert.equal(teaOrder.state,'ready');
    assert.ok(teaOrder.delivery_id);

    // Driver sees auto-dispatched food order in queue, claims, collects cash & delivers -> 80/20 wallet split + cash fee offset!
    const driverQueue=(await as(walletDriver,'delivery_cloud_list',[true,null,null])).orders;
    const queuedTea=driverQueue.find(o=>o.id===teaOrder.delivery_id);
    assert.ok(queuedTea);
    let trip1=await as(walletDriver,'delivery_cloud_transition',[queuedTea.id,'claim',queuedTea.version,randomUUID(),'']);
    trip1=await as(walletDriver,'delivery_cloud_transition',[trip1.id,'arrive',trip1.version,randomUUID(),'']);
    trip1=await as(walletDriver,'delivery_cloud_transition',[trip1.id,'pickup',trip1.version,randomUUID(),'']);
    trip1=await as(walletDriver,'delivery_cloud_transition',[trip1.id,'collect_cash',trip1.version,randomUUID(),'']);
    trip1=await as(walletDriver,'delivery_cloud_transition',[trip1.id,'deliver',trip1.version,randomUUID(),'Giao tra sua tan tay']);

    const fee1=trip1.shipping_fee;
    const share1=Math.round(fee1*0.80);
    const comm1=fee1-share1;
    let wSum=await as(walletDriver,'delivery_driver_wallet',['summary',{}]);
    assert.equal(Number(wSum.wallet.total_earned),share1);
    assert.equal(Number(wSum.wallet.total_commission),comm1);
    assert.equal(Number(wSum.wallet.balance),share1-fee1);

    // 5. Second trip with sender online-paid shipping fee (no cash_collected_fee) -> credits full +80% to wallet!
    const onlineDetails={
      pickup_address:'45 Ly Tu Trong, Quan 1, TP HCM',
      dropoff_address:'68 Nguyen Hue, Quan 1, TP HCM',
      recipient_name:'Khach An Uong',recipient_phone:'0942223344',
      package_description:'Ho so da thanh toan online',
      pickup_lat:10.7769,pickup_lng:106.6994,dropoff_lat:10.7745,dropoff_lng:106.7038,
      weight_kg:1,cod_amount:0,service_type:'express',payment_method:'sender_cash',
    };
    const q2=await as(foodBuyer,'delivery_cloud_quote',[onlineDetails]);
    const order2=await as(foodBuyer,'delivery_cloud_create',[onlineDetails,randomUUID(),q2.pricing_version,q2.shipping_fee]);
    await db.query("update delivery_cloud_orders set payment_status='PAID' where id=$1",[order2.id]);
    let trip2=await as(walletDriver,'delivery_cloud_transition',[order2.id,'claim',order2.version,randomUUID(),'']);
    trip2=await as(walletDriver,'delivery_cloud_transition',[trip2.id,'arrive',trip2.version,randomUUID(),'']);
    trip2=await as(walletDriver,'delivery_cloud_transition',[trip2.id,'pickup',trip2.version,randomUUID(),'']);
    trip2=await as(walletDriver,'delivery_cloud_transition',[trip2.id,'deliver',trip2.version,randomUUID(),'Da giao ho so']);
    const share2=Math.round(trip2.shipping_fee*0.80);
    wSum=await as(walletDriver,'delivery_driver_wallet',['summary',{}]);
    assert.equal(Number(wSum.wallet.balance),(share1-fee1)+share2);

    // 6. VietQR top-up request -> operator approves -> balance increases -> bank withdrawal locks funds -> cancel & approve flows
    const topupRes=await as(walletDriver,'delivery_driver_wallet',['request_topup',{amount:300000,driver_note:'Nap ky quy VietQR',request_key:randomUUID()}]);
    assert.equal(topupRes.request.kind,'topup');
    assert.equal(topupRes.request.state,'pending');
    assert.match(topupRes.request.transfer_code,/^GHST NAP /);
    await assert.rejects(as(walletDriver,'delivery_driver_wallet',['admin_resolve',{request_id:topupRes.request.id,decision:'approve',admin_note:'Thu trai phep'}]),e=>e.code==='PT403');
    await as(operator,'delivery_driver_wallet',['admin_resolve',{request_id:topupRes.request.id,decision:'approve',admin_note:'Da nhan VietQR 300k'}]);

    wSum=await as(walletDriver,'delivery_driver_wallet',['summary',{}]);
    const balAfterTopup=(share1-fee1)+share2+300000;
    assert.equal(Number(wSum.wallet.balance),balAfterTopup);

    await as(walletDriver,'delivery_driver_wallet',['save_bank',{
      bank_bin:'970422',bank_name:'MB Bank',bank_account_no:'0941112233',bank_account_name:'TAI XE VI CLOUD',
    }]);
    await assert.rejects(
      as(walletDriver,'delivery_driver_wallet',['request_withdraw',{amount:balAfterTopup+50000,request_key:randomUUID()}]),
      e=>e.code==='PT409'
    );
    const wdCancel=await as(walletDriver,'delivery_driver_wallet',['request_withdraw',{amount:100000,driver_note:'Rut thu',request_key:randomUUID()}]);
    wSum=await as(walletDriver,'delivery_driver_wallet',['summary',{}]);
    assert.equal(Number(wSum.wallet.balance),balAfterTopup-100000);
    assert.equal(Number(wSum.wallet.locked_balance),100000);
    await as(walletDriver,'delivery_driver_wallet',['cancel_request',{request_id:wdCancel.request.id}]);
    wSum=await as(walletDriver,'delivery_driver_wallet',['summary',{}]);
    assert.equal(Number(wSum.wallet.balance),balAfterTopup);
    assert.equal(Number(wSum.wallet.locked_balance),0);

    const wdApprove=await as(walletDriver,'delivery_driver_wallet',['request_withdraw',{amount:150000,driver_note:'Rut ve MB Bank',request_key:randomUUID()}]);
    const adminPending=await as(operator,'delivery_driver_wallet',['admin_list',{state:'pending'}]);
    assert.ok(adminPending.requests.some(r=>r.id===wdApprove.request.id));
    await as(operator,'delivery_driver_wallet',['admin_resolve',{request_id:wdApprove.request.id,decision:'approve',admin_note:'UNC MB998877'}]);
    wSum=await as(walletDriver,'delivery_driver_wallet',['summary',{}]);
    assert.equal(Number(wSum.wallet.balance),balAfterTopup-150000);
    assert.equal(Number(wSum.wallet.locked_balance),0);
    assert.equal(Number(wSum.wallet.total_withdrawn),150000);

    await assert.rejects(db.query('delete from delivery_driver_wallet_ledger'),/Immutable accounting record/);

    // 7. Showcase pause & purge (archives ordered tea shop, deletes unordered showcase shops cleanly)
    const pausedState=await as(operator,'delivery_showcase_catalog',['set_paused',{paused:true}]);
    assert.equal(pausedState.shops_active,0);
    const purgedState=await as(operator,'delivery_showcase_catalog',['purge',{}]);
    assert.equal(purgedState.seeded,false);
    assert.equal(purgedState.shops_total,1);
  });

  await check('P10 real-time GPS proximity 28s offer dispatch, corridor batching, dynamic pricing geofences and POD signature',async()=>{
    const p10Customer=randomUUID(),nearDriver=randomUUID(),midDriver=randomUUID();
    for(const [id,name,phone] of [
      [p10Customer,'Khach P10','0961112233'],
      [nearDriver,'Tai Xe Gan 400m','0962223344'],
      [midDriver,'Tai Xe Vua 2km','0963334455'],
    ]){
      await db.query('insert into auth.users values($1)',[id]);
      await as(id,'delivery_cloud_profile',[{full_name:name,phone,requested_role:'customer'}]);
    }
    for(const drv of [nearDriver,midDriver]){
      await as(drv,'delivery_cloud_membership',['driver','request']);
      await as(operator,'delivery_cloud_membership',['driver','approve',drv,1,'']);
    }

    // 1. Dynamic pricing rules + surge + ray-casting polygon geofence & optimistic version bump
    await assert.rejects(
      as(p10Customer,'delivery_admin_pricing',['save_rule',{service_type:'standard',base_fee:20000,per_km:5000}]),
      e=>e.code==='PT403'
    );
    const quotePayload={
      pickup_address:'12 Trang Tien, Hoan Kiem, Ha Noi',
      dropoff_address:'88 Ly Thuong Kiet, Hoan Kiem, Ha Noi',
      recipient_name:'Nguoi Nhan P10',recipient_phone:'0968889900',
      package_description:'Tai lieu P10',
      pickup_lat:21.0245,pickup_lng:105.8530,dropoff_lat:21.0265,dropoff_lng:105.8480,
      weight_kg:1.5,cod_amount:0,service_type:'standard',payment_method:'sender_cash',
      require_pod:true,require_signature:true,
    };
    const baseQuote=await as(p10Customer,'delivery_cloud_quote',[quotePayload]);
    assert.equal(baseQuote.breakdown.surge_fee,undefined);
    assert.equal(baseQuote.breakdown.geofence_fee,undefined);

    await as(operator,'delivery_admin_pricing',['save_rule',{
      service_type:'standard',base_fee:baseQuote.breakdown.base_fee,per_km:5000,
      peak_multiplier_bps:12000,peak_enabled:true,
      weather_surcharge:7000,weather_enabled:true,weather_label:'Mua lon Hoan Kiem',
    }]);
    const q1Polygon=[
      {lat:21.0200,lng:105.8450},
      {lat:21.0200,lng:105.8600},
      {lat:21.0320,lng:105.8600},
      {lat:21.0320,lng:105.8450},
    ];
    const pricingState=await as(operator,'delivery_admin_pricing',['save_geofence',{
      name:'Trung tam Hoan Kiem',zone_type:'surge',surcharge_fee:9000,multiplier_bps:10000,polygon:q1Polygon,active:true,
    }]);
    assert.equal(pricingState.geofences.length,1);

    // Stale quote version is rejected
    await assert.rejects(
      as(p10Customer,'delivery_cloud_create',[quotePayload,randomUUID(),baseQuote.pricing_version,baseQuote.shipping_fee]),
      e=>e.code==='PT409'
    );
    const surgedQuote=await as(p10Customer,'delivery_cloud_quote',[quotePayload]);
    const expectedPeak=Math.round(baseQuote.breakdown.base_fee*0.20);
    assert.equal(surgedQuote.breakdown.surge_fee,expectedPeak+7000);
    assert.equal(surgedQuote.breakdown.geofence_fee,9000);
    assert.deepEqual(surgedQuote.matched_geofences,['Trung tam Hoan Kiem']);
    assert.equal(surgedQuote.shipping_fee,baseQuote.shipping_fee+expectedPeak+7000+9000);

    // Outside polygon does not get geofence_fee
    const outsideQuote=await as(p10Customer,'delivery_cloud_quote',[{
      ...quotePayload,pickup_lat:21.0650,pickup_lng:105.8100,dropoff_lat:21.0680,dropoff_lng:105.8120,
    }]);
    assert.equal(outsideQuote.breakdown.geofence_fee,undefined);

    // 2. Real-time GPS proximity auto-dispatch: closest driver (~200m) gets exclusive 28s offer first; reject advances to midDriver (~1.8km)
    await as(nearDriver,'delivery_driver_dispatch',['set_presence',{
      is_online:true,latitude:21.0250,longitude:105.8532,heading:90,vehicle_type:'ev_scooter',
    }]);
    await as(midDriver,'delivery_driver_dispatch',['set_presence',{
      is_online:true,latitude:21.0410,longitude:105.8535,heading:180,vehicle_type:'motorbike',
    }]);

    const p10Order=await as(p10Customer,'delivery_cloud_create',[quotePayload,randomUUID(),surgedQuote.pricing_version,surgedQuote.payable_fee]);
    const nearPoll=await as(nearDriver,'delivery_driver_dispatch',['poll_offer',{}]);
    const midPollBefore=await as(midDriver,'delivery_driver_dispatch',['poll_offer',{}]);
    assert.ok(nearPoll.active_offer,'nearest driver receives exclusive 28s offer');
    assert.equal(nearPoll.active_offer.order_id,p10Order.id);
    assert.equal(nearPoll.active_offer.radius_tier_km,3);
    assert.ok(nearPoll.active_offer.remaining_seconds>0 && nearPoll.active_offer.remaining_seconds<=28);
    assert.equal(midPollBefore.active_offer,null,'offer is exclusive while pending');

    // nearDriver rejects -> offer immediately advances to midDriver!
    const rejRes=await as(nearDriver,'delivery_driver_dispatch',['respond_offer',{offer_id:nearPoll.active_offer.id,decision:'reject'}]);
    assert.equal(rejRes.rejected,true);
    const midPollAfter=await as(midDriver,'delivery_driver_dispatch',['poll_offer',{}]);
    assert.ok(midPollAfter.active_offer,'next closest driver immediately receives offer after rejection');
    assert.equal(midPollAfter.active_offer.order_id,p10Order.id);

    const accRes=await as(midDriver,'delivery_driver_dispatch',['respond_offer',{offer_id:midPollAfter.active_offer.id,decision:'accept'}]);
    assert.equal(accRes.accepted,true);
    assert.equal(accRes.order.status,'accepted');
    assert.equal(accRes.order.driver_id,midDriver);
    assert.equal(accRes.order.sender_profile.masked_phone,'0961***233');
    assert.equal(accRes.order.recipient_masked_phone,'0968***900');

    // 3. Recipient signature + POD photo independence on deliver
    let stepOrder=await as(midDriver,'delivery_cloud_transition',[p10Order.id,'arrive',accRes.order.version,randomUUID(),'']);
    stepOrder=await as(midDriver,'delivery_cloud_transition',[p10Order.id,'pickup',stepOrder.version,randomUUID(),'']);

    // Signature alone cannot bypass require_pod: true
    const sigPath=`${p10Order.tracking_code}/signature-${'a'.repeat(64)}.webp`;
    await db.query("insert into storage.objects(bucket_id,name) values('delivery-evidence',$1)",[sigPath]);
    await authenticatedQuery(midDriver,
      "insert into public.delivery_live_events(room_id,sender_id,kind,payload) values($1,$2,'pod',$3)",
      [p10Order.tracking_code,midDriver,JSON.stringify({path:sigPath,evidence_type:'signature',signer_name:'Nguoi Nhan P10'})]);
    await assert.rejects(
      as(midDriver,'delivery_cloud_transition',[p10Order.id,'deliver',stepOrder.version,randomUUID(),'Da ky']),
      e=>e.code==='PT409'
    );

    // Add photo POD -> now both require_pod and require_signature pass!
    const podPath=`${p10Order.tracking_code}/pod-${'b'.repeat(64)}.webp`;
    await db.query("insert into storage.objects(bucket_id,name) values('delivery-evidence',$1)",[podPath]);
    await authenticatedQuery(midDriver,
      "insert into public.delivery_live_events(room_id,sender_id,kind,payload) values($1,$2,'pod',$3)",
      [p10Order.tracking_code,midDriver,JSON.stringify({path:podPath,evidence_type:'photo'})]);
    stepOrder=await as(midDriver,'delivery_cloud_transition',[p10Order.id,'deliver',stepOrder.version,randomUUID(),'Da giao du POD va chu ky']);
    assert.equal(stepOrder.status,'delivered');
    assert.equal(stepOrder.has_pod,true);
    assert.equal(stepOrder.has_signature,true);
    assert.equal(stepOrder.pod_photo_path,podPath);
    assert.equal(stepOrder.signature_path,sigPath);
    assert.equal(stepOrder.recipient_signer_name,'Nguoi Nhan P10');

    // 4. Multi-Order Route Batching (Trip Bundle): 2 compatible orders in same corridor
    await as(nearDriver,'delivery_driver_dispatch',['set_presence',{is_online:false}]);
    await as(midDriver,'delivery_driver_dispatch',['set_presence',{is_online:false}]);
    await as(operator,'delivery_admin_pricing',['reset_rules',{}]);
    await as(operator,'delivery_admin_pricing',['delete_geofence',{id:pricingState.geofences[0].id}]);

    const b1Details={
      pickup_address:'10 Trang Thi, Hoan Kiem, Ha Noi',
      dropoff_address:'200 Kim Ma, Ba Dinh, Ha Noi',
      recipient_name:'Khach Ghep 1',recipient_phone:'0971112233',package_description:'Hop A',
      pickup_lat:21.0260,pickup_lng:105.8490,dropoff_lat:21.0330,dropoff_lng:105.8250,
      weight_kg:1,cod_amount:0,service_type:'saving',payment_method:'sender_cash',
    };
    const b2Details={
      pickup_address:'25 Hai Ba Trung, Hoan Kiem, Ha Noi',
      dropoff_address:'240 Doi Can, Ba Dinh, Ha Noi',
      recipient_name:'Khach Ghep 2',recipient_phone:'0972223344',package_description:'Hop B',
      pickup_lat:21.0245,pickup_lng:105.8505,dropoff_lat:21.0355,dropoff_lng:105.8230,
      weight_kg:1.2,cod_amount:50000,service_type:'saving',payment_method:'sender_cash',
    };
    const qb1=await as(p10Customer,'delivery_cloud_quote',[b1Details]);
    const qb2=await as(p10Customer,'delivery_cloud_quote',[b2Details]);
    const ob1=await as(p10Customer,'delivery_cloud_create',[b1Details,randomUUID(),qb1.pricing_version,qb1.payable_fee]);
    const ob2=await as(p10Customer,'delivery_cloud_create',[b2Details,randomUUID(),qb2.pricing_version,qb2.payable_fee]);

    const bundleRes=await as(nearDriver,'delivery_driver_dispatch',['batch_suggestions',{}]);
    const matchedBundle=bundleRes.bundles.find(b=>b.order_ids.includes(ob1.id)&&b.order_ids.includes(ob2.id));
    assert.ok(matchedBundle,'corridor batch suggestion pairs compatible orders');
    assert.equal(Number(matchedBundle.estimated_earning),Math.round((ob1.shipping_fee+ob2.shipping_fee)*0.80));

    const claimBatchRes=await as(nearDriver,'delivery_driver_dispatch',['claim_batch',{order_ids:[ob1.id,ob2.id],request_key:randomUUID()}]);
    assert.ok(claimBatchRes.batch_group_id);
    assert.equal(claimBatchRes.orders.length,2);
    assert.ok(claimBatchRes.orders.every(o=>o.status==='accepted'&&o.driver_id===nearDriver&&o.batch_group_id===claimBatchRes.batch_group_id));
  });
  const output=path.resolve(import.meta.dirname,'../../../build/verification/postgres-acceptance.json');
  await mkdir(path.dirname(output),{recursive:true});
  await writeFile(output,JSON.stringify({environment:'disposable-loopback-postgresql',checkedAt:new Date().toISOString(),durationMs:Date.now()-startedAt,results},null,2));
  console.log('PostgreSQL acceptance complete. No cloud writes or provider transactions.');
}finally{
  await pool.end();await db.end();await cluster.stop();
}
