<template>
  <div class="l-box">
    <div class="retry-message" v-if="showRetryMessage">
      {{ retryMessage }}
    </div>
    <div class="dy-form">
      <div class="dy-title">房间信息</div>
      <div
        class="dy-room-box"
        :class="{
          error: rnFlag
        }">
        <div class="dy-room-tag">房间号</div>
        <input
          v-model="roomNum"
          type="text"
          class="dy-room-input"
          placeholder="请输入12位房间号"
          :disabled="connectCode === 200"
        />
        <button 
          class="dy-room-btn"
          :class="{ 'disconnect': connectCode === 200 }"
          @click="connectCode === 200 ? disconnect() : gotoConnect()"
          :disabled="isConnecting"
        >
          {{ isConnecting ? '连接中...' : (connectCode === 200 ? '断开连接' : '连接') }}
        </button>
      </div>
      <div class="dy-title">转发信息</div>
      <div class="dy-room-box">
        <div class="dy-room-tag">ws地址</div>
        <input 
          v-model="relayWs" 
          type="text" 
          class="dy-room-input" 
          placeholder="请输入ws/wss协议链接"
          :disabled="isRelaying" 
        />
        <button 
          class="dy-room-btn"
          :class="{ 'relaying': isRelaying }"
          @click="isRelaying ? stopRelay() : relay()"
        >
          {{ isRelaying ? '停止转发' : '转发' }}
        </button>
      </div>
      <div class="dy-title">
        <span>房间信息</span>
        <span
          v-if="connectCode !== 100"
          class="state"
          :class="{
            success: connectCode === 200,
            fail: connectCode === 400
          }"
          >{{ connectCode === 200 ? '连接成功' : '连接失败' }}</span
        >
      </div>
      <div class="dy-room-info" v-if="connectCode !== 100">
        <div class="title-box">
          <img :src="roomAvatar" alt="头像" />
          <span>{{ roomTitle }}</span>
        </div>
        <div class="info-item">
          <span class="tit">主播粉丝数：</span>
          <span class="text">{{ followCount }}</span>
        </div>
        <div class="info-item">
          <span class="tit">累计观看人数：</span>
          <span class="text">{{ totalUserCount }}</span>
        </div>
        <div class="info-item">
          <span class="tit">在线观众数：</span>
          <span class="text">{{ memberCount }}</span>
        </div>
        <div class="info-item">
          <span class="tit">点赞数：</span>
          <span class="text">{{ likeCount }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { DyClient, handleMessage } from '../utils/client';
import { getRoomInfoApi } from '@/api/commonApi';
import { ref, inject, onMounted, type Ref } from 'vue';

// 房间号
const roomNum = ref<string | null>(null);

// 将 relayWs 的默认值设置为 'ws://localhost:3001'
const relayWs = ref<string>('ws://localhost:3001');
// 弹幕列表
const chatList = inject<Mess[]>('chatList');
// 点赞送礼榜
const rankList = inject<RankItem[]>('rankList');

// 连接状态
const connectCode = ref<number>(100);
const roomAvatar = ref<string>('');
const roomTitle = ref<string | null>(null);

const isStopScroll = inject<Ref<boolean>>('isStopScroll');
const setIsStopScroll = inject<(value: boolean) => void>('setIsStopScroll');

const rnFlag = ref(false);
/**
 * 在线观众
 */
const memberCount = ref(0);
/**
 * 点赞数
 */
const likeCount = ref(0);
/**
 * 主播粉丝数
 */
const followCount = ref(0);
/**
 * 累计观看人数
 */
const totalUserCount = ref(0);

// 传送的socket
let relaySocket: any;
// 消息列表DOM
let messListDom: HTMLElement | null;

// 添加主题注入
const isDarkTheme = inject<Ref<boolean>>('isDarkTheme');

// 在 script setup 中添加新的 ref
const isConnecting = ref(false);

// 在 ref 声明区域添加重试次数计数器
const retryCount = ref(0);
const MAX_RETRIES = 2; // 最大重试次数

// 在 script setup 中添加 client 变量
let dyClient: any = null;

// 添加转发状态标志
const isRelaying = ref(false);

// 添加重连相关的常量和变量
const MAX_RELAY_RETRIES = 3; // 最大重连次数
const RELAY_RETRY_DELAY = 3000; // 重连延迟时间（毫秒）
const relayRetryCount = ref(0); // 重连计数器

// 在 ref 声明区域添加新的状态
const retryMessage = ref('');
const showRetryMessage = ref(false);

// 修改获取 URL 参数的函数，添加 roomId 参数的获取
function getUrlParam(name: string): string | null {
  const urlParams = new URLSearchParams(window.location.search);
  return urlParams.get(name);
}

// 添加 roomId ref 的获取
const urlRoomId = getUrlParam('roomId');

// 添加 productId ref
const productId = ref<string | null>(getUrlParam('productId'));

onMounted(() => {
  messListDom = document.getElementById('mess-list');
  
  // 如果 URL 中存在 roomId，自动填入并连接
  if (urlRoomId) {
    roomNum.value = urlRoomId;
    gotoConnect();
  }
});

/**
 * 连接直播间
 */
function gotoConnect() {
  // 如果正在连接中，直接返回
  if (isConnecting.value) return;
  
  if (!roomNum.value) {
    rnFlag.value = true;
    return;
  }
  if (!/\d{8,12}/.test(roomNum.value)) {
    rnFlag.value = true;
    return;
  }
  rnFlag.value = false;
  
  // 设置连接状态
  isConnecting.value = true;

  // 清空聊天列表和排行榜
  if (chatList) chatList.length = 0;
  if (rankList) rankList.length = 0;

  // 创建一个隐藏的 iframe
  const iframe = document.createElement('iframe');
  iframe.style.display = 'none';
  iframe.src = `https://live.douyin.com/${roomNum.value}`;
  document.body.appendChild(iframe);

  // 2秒后移除iframe并获取房间信息
  setTimeout(() => {
    document.body.removeChild(iframe);
    roomNum.value &&
      getRoomInfoApi(roomNum.value)
        .then((res: any) => {
          roomAvatar.value = res.avatar;
          roomTitle.value = res.roomTitle;
          if (!res.roomId || !res.uniqueId) {
            // 房间ID和uniqueID获取失败
            handleConnectionError();
          } else {
            // 连接成功，重置重试计数
            retryCount.value = 0;
            connection(res.roomId, res.uniqueId);
          }
        })
        .catch((err: any) => {
          console.error(err);
          handleConnectionError();
        })
        .finally(() => {
          // 重置连接状态
          isConnecting.value = false;
        });
  }, 2000);
}

/**
 * 转发消息
 */
function relay() {
  if (!relayWs.value) {
    console.error('转发地址不能为空');
    return;
  }

  isRelaying.value = true;
  
  // 构建 WebSocket URL
  let wsUrl = relayWs.value;
  if (productId.value) {
    const separator = wsUrl.includes('?') ? '&' : '?';
    wsUrl = `${wsUrl}${separator}productId=${productId.value}&type=danmu`;
  }
  
  try {
    relaySocket = new WebSocket(wsUrl);
    
    relaySocket.onopen = () => {
      console.log('转发WebSocket连接成功');
      // 连接成功时重置重试计数
      relayRetryCount.value = 0;
    };
    
    relaySocket.onerror = (error: Event) => {
      console.error('转发WebSocket连接错误:', error);
      handleRelayError();
    };
    
    relaySocket.onclose = (event: CloseEvent) => {
      console.log('转发WebSocket连接已关闭', event.code, event.reason);
      // 只有在isRelaying为true时才尝试重连
      // 排除主动关闭的情况（代码1000表示正常关闭）
      if (isRelaying.value && event.code !== 1000) {
        handleRelayError();
      } else {
        isRelaying.value = false;
      }
    };
  } catch (error) {
    console.error('创建WebSocket连接失败:', error);
    handleRelayError();
  }
}

/**
 * 链接弹幕
 * @param roomId
 * @param uniqueId
 */
function connection(roomId: string, uniqueId: string) {
  let sign = window.getSign(roomId, uniqueId)['X-Bogus'];
  let now = Date.now();
  let wsUrl = `wss://webcast3-ws-web-hl.douyin.com/webcast/im/push/v2/?app_name=douyin_web&version_code=180800&webcast_sdk_version=1.3.0&update_version_code=1.3.0&compress=gzip&internal_ext=internal_src:dim|wss_push_room_id:${roomId}|wss_push_did:${uniqueId}|fetch_time:${now}|seq:1|wss_info:0-${now}-0-0&cursor=t-${now}_r-1_d-1_u-1_h-1&host=https://live.douyin.com&aid=6383&live_id=1&did_rule=3&debug=false&maxCacheMessageNumber=20&endpoint=live_pc&support_wrds=1&im_path=/webcast/im/fetch/&user_unique_id=${uniqueId}&device_platform=web&cookie_enabled=true&screen_width=1920&screen_height=1080&browser_language=zh-CN&browser_platform=Win32&browser_name=Mozilla&browser_version=5.0%20(Windows%20NT%2010.0;%20Win64;%20x64)%20AppleWebKit/537.36%20(KHTML,%20like%20Gecko)%20Chrome/111.0.0.0%20Safari/537.36%20Edg/111.0.1661.62&browser_online=true&tz_name=Asia/Shanghai&identity=audience&room_id=${roomId}&heartbeatDuration=0&signature=${sign}`;
  // 服务地址 发送
  dyClient = new DyClient();
  dyClient.init(wsUrl);
  dyClient.accept = (message: proto.Message) => {
    if (message) {
      let m = handleMessage(message);
      handleChat(m);
      renewPos();
      relayMess(m);
    }
  };
  dyClient.onOff = (flag: boolean) => {
    if (flag) {
      connectCode.value = 200;
      // 连接成功后，如果有设置转发地址且未在转发中，则自动开始转发
      if (relayWs.value && !isRelaying.value) {
        relay();
      }
    } else {
      connectCode.value = 400;
    }
  };
}

/**
 * 处理信息
 * @param chat
 */
function handleChat(data: Mess) {
  let type = data.type;
  switch (type) {
    case 'chat':
      chatList!.push(data);
      break;
    case 'member':
      memberCount.value = data.memberCount;
      break;
    case 'like':
      likeCount.value = data.likeCount;
      break;
    case 'gift':
      chatList!.push(data);
      break;
    case 'social':
      followCount.value = data.followCount;
      break;
    case 'room':
      memberCount.value = data.memberCount;
      totalUserCount.value = data.totalUserCount;
      rankList!.length = 0;
      rankList!.push(...data.rank);
      break;
  }
}

/**
 * 更新消息列表位置
 */
function renewPos() {
  if (!messListDom) {
    messListDom = document.getElementById('mess-list');
  }
  // console.log(isStopScroll?.value);
  if (!isStopScroll?.value) {
    messListDom &&
      messListDom.scrollTo({ top: messListDom.scrollHeight - messListDom.clientHeight, behavior: 'smooth' });
  }
}

/**
 * 转发消息
 * @param data
 */
function relayMess(data: Mess) {
  if (!data.type) return;
  // 检查WebSocket是否已连接
  if (relaySocket && relaySocket.readyState === WebSocket.OPEN) {
    relaySocket.send(JSON.stringify(data));
  } else {
    console.log('WebSocket未连接，无法发送消息');
  }
}

// 修改 handleConnectionError 函数
function handleConnectionError() {
  if (retryCount.value < MAX_RETRIES) {
    retryCount.value++;
    showRetryMessage.value = true;
    retryMessage.value = `连接失败，正在进行第 ${retryCount.value} 次重试...`;
    // 添加3秒后自动关闭消息提示
    setTimeout(() => {
      showRetryMessage.value = false;
    }, 3000);
    setTimeout(() => {
      gotoConnect();
    }, 2000);
  } else {
    connectCode.value = 400;
    retryCount.value = 0;
    showRetryMessage.value = true;
    retryMessage.value = '连接失败，请检查房间号是否正确后重试';
    setTimeout(() => {
      showRetryMessage.value = false;
    }, 3000);
  }
}

// 修改 handleRelayError 函数
function handleRelayError() {
  if (relayRetryCount.value < MAX_RELAY_RETRIES) {
    relayRetryCount.value++;
    showRetryMessage.value = true;
    retryMessage.value = `转发连接断开，${RELAY_RETRY_DELAY/1000}秒后进行第 ${relayRetryCount.value} 次重试...`;
    // 添加3秒后自动关闭消息提示
    setTimeout(() => {
      showRetryMessage.value = false;
    }, 3000);
    
    if (relaySocket) {
      try {
        relaySocket.close();
      } catch (e) {
        // 忽略关闭错误
      }
      relaySocket = null;
    }
    
    setTimeout(() => {
      if (isRelaying.value && connectCode.value === 200) {
        relay();
      }
    }, RELAY_RETRY_DELAY);
  } else {
    console.error('转发重连次数已达上限，停止重连');
    showRetryMessage.value = true;
    retryMessage.value = '转发连接失败，请检查地址是否正确后重试';
    setTimeout(() => {
      showRetryMessage.value = false;
    }, 3000);
    isRelaying.value = false;
    relayRetryCount.value = 0;
  }
}

// 修改 stopRelay 函数，确保清理状态
function stopRelay() {
  isRelaying.value = false;
  relayRetryCount.value = 0;
  
  if (relaySocket) {
    try {
      // 使用正常关闭代码1000
      relaySocket.close(1000, '用户主动停止转发');
      relaySocket = null;
    } catch (error) {
      console.error('关闭转发连接时发生错误:', error);
    }
  }
}

// 修改断开连接函数，移除清空列表的逻辑
function disconnect() {
  if (dyClient) {
    try {
      // 清理资源并关闭连接
      dyClient.destroy();
      dyClient = null;
    } catch (error) {
      console.error('断开连接时发生错误:', error);
    }
  }
  
  // 同时停止转发
  stopRelay();
  
  // 重置所有状态
  connectCode.value = 100;
  isConnecting.value = false;
  roomAvatar.value = '';
  roomTitle.value = null;
  memberCount.value = 0;
  likeCount.value = 0;
  followCount.value = 0;
  totalUserCount.value = 0;
}
</script>

<style lang="less" scoped>
.retry-message {
  position: fixed;
  top: 20px;
  left: 50%;
  transform: translateX(-50%);
  background-color: v-bind('isDarkTheme ? "rgba(0,0,0,0.8)" : "rgba(255,255,255,0.9)"');
  color: v-bind('isDarkTheme ? "#fff" : "#333"');
  padding: 10px 20px;
  border-radius: 4px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.2);
  z-index: 1000;
  animation: fadeIn 0.3s ease;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translate(-50%, -20px);
  }
  to {
    opacity: 1;
    transform: translate(-50%, 0);
  }
}

.dy-form {
  width: 100%;
  height: 100%;
  box-sizing: border-box;
  display: flex;
  padding: 24px 36px;
  flex-direction: column;
  .dy-title {
    position: relative;
    font-size: 18px;
    font-weight: bold;
    padding: 8px 5px;
    border-bottom: 1px solid v-bind('isDarkTheme ? "#333" : "#ccc"');
    margin-bottom: 8px;
    color: v-bind('isDarkTheme ? "#fff" : "#000"');
    .state {
      position: absolute;
      right: 12px;
      font-size: 16px;
      font-weight: normal;
      &.success {
        color: #98d98e;
      }
      &.fail {
        color: #f7315d;
      }
    }
  }
  .dy-room-box {
    max-width: 420px;
    height: 36px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    border: 1px solid v-bind('isDarkTheme ? "#333" : "#9aa7b1"');
    border-radius: 5px;
    overflow: hidden;
    box-sizing: border-box;
    margin: 12px 8px;
    margin-bottom: 24px;
    flex-shrink: 0;
    background-color: v-bind('isDarkTheme ? "#1a1a1a" : "#fff"');
    &.error {
      border-color: #fa5232;
    }
    .dy-room-tag {
      flex-shrink: 0;
      text-align: center;
      padding: 0 12px;
      box-sizing: border-box;
      color: v-bind('isDarkTheme ? "#fff" : "#000"');
    }
    .dy-room-input {
      min-width: 114px;
      height: 100%;
      font-size: 14px;
      color: v-bind('isDarkTheme ? "#fff" : "#5c4f55"');
      flex-grow: 1;
      height: 100%;
      outline: none;
      border: none;
      padding: 0;
      background-color: transparent;
      &:disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }
    }
    .dy-room-btn {
      cursor: pointer;
      user-select: none;
      flex-shrink: 0;
      outline: none;
      height: 100%;
      border: none;
      padding: 0;
      box-sizing: border-box;
      padding: 0 24px;
      background-color: v-bind('isDarkTheme ? "#333" : "#a9b7c2"');
      color: v-bind('isDarkTheme ? "#fff" : "#000"');
      &:disabled {
        cursor: not-allowed;
        opacity: 0.6;
      }
      &.disconnect {
        background-color: v-bind('isDarkTheme ? "#f44336" : "#ff6b6b"');
        
        &:hover {
          background-color: v-bind('isDarkTheme ? "#d32f2f" : "#ff5252"');
        }
      }
      &.relaying {
        background-color: v-bind('isDarkTheme ? "#ff9800" : "#ffa726"');
        
        &:hover {
          background-color: v-bind('isDarkTheme ? "#f57c00" : "#ff9100"');
        }
      }
    }
  }
  .dy-room-info {
    display: flex;
    flex-direction: column;
    box-sizing: border-box;
    padding: 12px 8px;
    .title-box {
      display: flex;
      align-items: center;
      margin: 12px 0;
      img {
        border-radius: 50%;
        width: 64px;
        height: 64px;
        border: 1px solid v-bind('isDarkTheme ? "#333" : "#ccc"');
      }
      span {
        margin-left: 12px;
        font-size: 16px;
        font-weight: bold;
        color: v-bind('isDarkTheme ? "#ccc" : "#8b968d"');
      }
    }
    .info-item {
      font-size: 14px;
      font-weight: bold;
      & + .info-item {
        margin-top: 8px;
      }
      .tit {
        margin-right: 12px;
        color: v-bind('isDarkTheme ? "#ccc" : "#333631"');
      }
      .text {
        color: v-bind('isDarkTheme ? "#999" : "#9e9478"');
      }
    }
  }
  
  // 添加主题切换过渡效果
  transition: all 0.3s ease;
  
  .dy-title {
    transition: all 0.3s ease;
  }
  
  .dy-room-box {
    transition: all 0.3s ease;
    
    .dy-room-input {
      transition: all 0.3s ease;
    }
    
    .dy-room-btn {
      transition: all 0.3s ease;
      
      &:hover {
        background-color: v-bind('isDarkTheme ? "#444" : "#bac5cd"');
      }
    }
  }
  
  .dy-room-info {
    transition: all 0.3s ease;
    
    .title-box {
      img {
        transition: all 0.3s ease;
      }
      span {
        transition: all 0.3s ease;
      }
    }
    
    .info-item {
      .tit, .text {
        transition: all 0.3s ease;
      }
    }
  }
}
</style>
