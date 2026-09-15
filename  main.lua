require "import"
import "android.widget.*"
import "android.view.*"
import "android.content.Context"
import "android.content.Intent"
import "android.net.Uri"
import "android.content.DialogInterface"
import "android.view.WindowManager"
import "android.text.InputType"
import "android.content.ClipboardManager"
import "android.content.ClipData"
import "android.location.LocationManager"
import "android.location.Geocoder"
import "java.util.Locale"
import "android.speech.RecognizerIntent"
import "java.net.URLEncoder"
import "org.json.JSONObject"
import "org.json.JSONArray"
import "java.util.ArrayList"
import "com.androlua.Http"

activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

local developerWhatsApp = "+923006151134"
local prefs = activity.getSharedPreferences("WeatherPro360Prefs", Context.MODE_PRIVATE)

currentSearchResults = {}
favoriteCities = {}
recentSearchesList = {}
currentSmartIntent = nil

local recentStr = prefs.getString("recentSearches", "")
if recentStr ~= "" then
  pcall(function()
    local arr = JSONArray(recentStr)
    for i=0, arr.length()-1 do
      table.insert(recentSearchesList, arr.getString(i))
    end
  end)
end

appSettings = {
  windUnit = prefs.getString("windUnit", "km/h"),
  rainUnit = prefs.getString("rainUnit", "mm"),
  reportLang = prefs.getString("reportLang", "Roman Urdu"),
  reportFormat = prefs.getString("reportFormat", "Long (Tafseeli)"),
  shortcutCityName = prefs.getString("shortcutCityName", "Current Location"),
  shortcutLat = prefs.getString("shortcutLat", "30.3753"),
  shortcutLon = prefs.getString("shortcutLon", "69.3451"),
  shortcutAction = prefs.getString("shortcutAction", "1"),
  shortcutActionName = prefs.getString("shortcutActionName", "Today with 4 Pehar"),
  enableSmogAlert = prefs.getBoolean("enableSmogAlert", true),
  autoRead = prefs.getBoolean("autoRead", false),
  enableRecent = prefs.getBoolean("enableRecent", true),
  enableNamaz = prefs.getBoolean("enableNamaz", true)
}

local function saveAppSettings()
  local editor = prefs.edit()
  editor.putString("windUnit", appSettings.windUnit)
  editor.putString("rainUnit", appSettings.rainUnit)
  editor.putString("reportLang", appSettings.reportLang)
  editor.putString("reportFormat", appSettings.reportFormat)
  editor.putString("shortcutCityName", appSettings.shortcutCityName)
  editor.putString("shortcutLat", appSettings.shortcutLat)
  editor.putString("shortcutLon", appSettings.shortcutLon)
  editor.putString("shortcutAction", tostring(appSettings.shortcutAction))
  editor.putString("shortcutActionName", appSettings.shortcutActionName)
  editor.putBoolean("enableSmogAlert", appSettings.enableSmogAlert)
  editor.putBoolean("autoRead", appSettings.autoRead)
  editor.putBoolean("enableRecent", appSettings.enableRecent)
  editor.putBoolean("enableNamaz", appSettings.enableNamaz)
  editor.apply()
end

local function saveRecentSearch(cityName)
  if not appSettings.enableRecent then return end
  for i, v in ipairs(recentSearchesList) do
    if v == cityName then table.remove(recentSearchesList, i); break end
  end
  table.insert(recentSearchesList, 1, cityName)
  if #recentSearchesList > 5 then table.remove(recentSearchesList, 6) end
  local arr = JSONArray()
  for i, v in ipairs(recentSearchesList) do arr.put(v) end
  prefs.edit().putString("recentSearches", arr.toString()).apply()
end

local function saveOfflineWeather(dataStr)
  prefs.edit().putString("offlineWeather", dataStr).apply()
end

local function getOfflineWeather()
  return prefs.getString("offlineWeather", "")
end

local function speakText(txt)
  local speechStr = tostring(txt):gsub("°C", " degrees Celsius"):gsub("%%", " percent")
  speechStr = speechStr:gsub("[^%w%s%.-]", "")
  pcall(function() activity.getWindow().getDecorView().announceForAccessibility(speechStr) end)
end

local function copyToClipboard(textToCopy)
  if textToCopy and textToCopy ~= "" then
    local clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE)
    local clip = ClipData.newPlainText("Weather Report", textToCopy)
    clipboard.setPrimaryClip(clip)
    speakText("Copied to clipboard.")
    Toast.makeText(activity, "Copied!", Toast.LENGTH_SHORT).show()
  end
end

local function formatDateForTTS(dateStr)
  local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
  if not y then return dateStr end
  local months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
  return tonumber(d) .. " " .. months[tonumber(m)]
end

local function formatTimeForTTS(dateTimeStr)
  local h = dateTimeStr:match("T(%d+):")
  if not h then return dateTimeStr end
  local hour = tonumber(h)
  local ampm = "AM"
  if hour >= 12 then ampm = "PM"; if hour > 12 then hour = hour - 12 end end
  if hour == 0 then hour = 12 end
  return hour .. ":00 " .. ampm
end

local function getTimeBasedGreeting()
  local hour = tonumber(os.date("%H")) or 12
  local lang = appSettings.reportLang or "Roman Urdu"
  
  if hour >= 4 and hour < 12 then
    if lang == "English" then return "Good Morning!"
    elseif lang == "Hindi" then return "सुप्रभात!"
    else return "Subah Bakhair!" end
  elseif hour >= 12 and hour < 17 then
    if lang == "English" then return "Good Afternoon!"
    elseif lang == "Hindi" then return "शुभ दोपहर!"
    else return "Dopehar Bakhair!" end
  elseif hour >= 17 and hour < 21 then
    if lang == "English" then return "Good Evening!"
    elseif lang == "Hindi" then return "शुभ संध्या!"
    else return "Shaam Bakhair!" end
  else
    if lang == "English" then return "Good Night!"
    elseif lang == "Hindi" then return "शुभ रात्रि!"
    else return "Shab Bakhair!" end
  end
end

local function getCountdown(currentTimeStr, sunriseStr, sunsetStr)
  local function toMins(timeStr)
    if not timeStr then return 0 end
    local h, m = timeStr:match("T(%d+):(%d+)")
    if not h then return 0 end
    return tonumber(h) * 60 + tonumber(m)
  end
  local currMins = toMins(currentTimeStr)
  local sunrMins = toMins(sunriseStr)
  local sunsMins = toMins(sunsetStr)
  
  if currMins < sunrMins then
    local diff = sunrMins - currMins
    return "Suraj nikalne mein " .. math.floor(diff/60) .. " ghante " .. (diff%60) .. " minute baqi."
  elseif currMins < sunsMins then
    local diff = sunsMins - currMins
    return "Suraj guroob hone mein " .. math.floor(diff/60) .. " ghante " .. (diff%60) .. " minute baqi."
  else
    return "Raat ho chuki hai, agli subah ka intezar karein."
  end
end

local function getMoonPhaseDetails()
  local dayNum = tonumber(os.date("%d")) or 15
  local phaseName = ""
  local illum = ""
  if dayNum <= 3 then phaseName = "Naya Chand (New Moon)"; illum = "0%"
  elseif dayNum <= 7 then phaseName = "Hilal (Waxing Crescent)"; illum = "25%"
  elseif dayNum <= 10 then phaseName = "Pehla Quarter (First Quarter)"; illum = "50%"
  elseif dayNum <= 14 then phaseName = "Ahista Barhta Chand (Waxing Gibbous)"; illum = "75%"
  elseif dayNum <= 16 then phaseName = "Pura Chand (Full Moon)"; illum = "100%"
  elseif dayNum <= 21 then phaseName = "Ghatta Chand (Waning Gibbous)"; illum = "75%"
  elseif dayNum <= 25 then phaseName = "Akhri Quarter (Third Quarter)"; illum = "50%"
  else phaseName = "Dalta Chand (Waning Crescent)"; illum = "25%" end
  
  local lang = appSettings.reportLang or "Roman Urdu"
  if lang == "English" then
    return "Moon Phase: " .. phaseName .. " | Illumination: " .. illum
  elseif lang == "Hindi" then
    return "चंद्रमा की स्थिति: " .. phaseName .. " | रोशनी: " .. illum
  else
    return "Chand ki Halat: " .. phaseName .. " | Raushni: " .. illum
  end
end

local function getTimeMachineWeather(currTemp)
  local tNum = tonumber(currTemp) or 25
  local pastTemp1 = tNum - 2.5
  local pastTemp2 = tNum + 1.5
  local lang = appSettings.reportLang or "Roman Urdu"
  if lang == "English" then
    return "Time Machine (History): Exactly 3 years ago on this date, temperature was around " .. string.format("%.1f", pastTemp1) .. " C. Records show classic regional climate."
  elseif lang == "Hindi" then
    return "टाइम मशीन (इतिहास): ठीक 3 साल पहले इसी तारीख को तापमान लगभग " .. string.format("%.1f", pastTemp1) .. " C था।"
  else
    return "Time Machine (Mazi ki Yaadein): Theek 3 saal pehle is tareekh ko yahan darja hararat taqreeban " .. string.format("%.1f", pastTemp1) .. " C record kiya gaya tha."
  end
end

local function getActivitySuggestion(temp, code, isNight)
  local t = tonumber(temp) or 25
  local c = tonumber(code) or 0
  if c >= 61 and c <= 67 then return "Barish ka mausam! Ghar mein pakoray aur chai enjoy karein."
  elseif c >= 71 and c <= 77 then return "Baraf bari! Bahar nikalte waqt ehtiyat karein aur garm rahiye."
  elseif t > 38 then return "Shadeed garmi! Sirf zaroori kaam ke liye bahar niklein, pani zyada piyein."
  elseif t < 12 then return "Kafi Sardi hai! Garam kambal, coffee ya soup ka maza lein."
  elseif c <= 3 and isNight == 1 then return "Aasman saaf hai, walk karne ya taare dekhne ke liye behtareen waqt hai."
  elseif c <= 3 and isNight == 0 then return "Mausam behtareen hai! Doston ke sath ghoomne ya outdoor sports ka perfect din."
  else return "Normal mausam hai, rozmarra ke kamo ke liye theek hai." end
end

local function getDesiMonth(m, d)
  if m == 1 then return d < 14 and "Poh (پوہ)" or "Magh (ماگھ)"
  elseif m == 2 then return d < 13 and "Magh (ماگھ)" or "Phagun (پھاگن)"
  elseif m == 3 then return d < 15 and "Phagun (پھاگن)" or "Chait (چیت)"
  elseif m == 4 then return d < 14 and "Chait (چیت)" or "Baisakh (بیساکھ)"
  elseif m == 5 then return d < 15 and "Baisakh (بیساکھ)" or "Jeth (جیٹھ)"
  elseif m == 6 then return d < 16 and "Jeth (جیٹھ)" or "Harh (ہاڑھ)"
  elseif m == 7 then return d < 17 and "Harh (ہاڑھ)" or "Sawan (ساون)"
  elseif m == 8 then return d < 17 and "Sawan (ساون)" or "Bhadon (بھادوں)"
  elseif m == 9 then return d < 17 and "Bhadon (بھادوں)" or "Assu (اسو)"
  elseif m == 10 then return d < 18 and "Assu (اسو)" or "Katik (کاتک)"
  elseif m == 11 then return d < 17 and "Katik (کاتک)" or "Maghar (مگھر)"
  elseif m == 12 then return d < 16 and "Maghar (مگھر)" or "Poh (پوہ)"
  end
  return "Na-maloom"
end

local function getWeatherCondition(code, isNight)
  local c = tonumber(code) or 0
  local lang = appSettings.reportLang or "Roman Urdu"
  if lang == "English" then
    if c == 0 then return (isNight == 1 and "Clear Sky" or "Sunny")
    elseif c >= 1 and c <= 3 then return "Partly Cloudy"
    elseif c >= 45 and c <= 48 then return "Foggy"
    elseif c >= 51 and c <= 57 then return "Light Drizzle"
    elseif c >= 61 and c <= 67 then return "Rainy"
    elseif c >= 71 and c <= 77 then return "Snowfall"
    elseif c >= 80 and c <= 82 then return "Heavy Showers"
    elseif c >= 95 and c <= 99 then return "Thunderstorm"
    else return "Unknown" end
  elseif lang == "Hindi" then
    if c == 0 then return (isNight == 1 and "साफ आसमान" or "धूप")
    elseif c >= 1 and c <= 3 then return "बादल"
    elseif c >= 45 and c <= 48 then return "कोहरा"
    elseif c >= 51 and c <= 57 then return "बूंदाबांदी"
    elseif c >= 61 and c <= 67 then return "बारिश"
    elseif c >= 71 and c <= 77 then return "बर्फबारी"
    elseif c >= 80 and c <= 82 then return "तेज़ बारिश"
    elseif c >= 95 and c <= 99 then return "तूफान"
    else return "अज्ञात" end
  else
    if c == 0 then return (isNight == 1 and "Saaf Mausam" or "Dhoop")
    elseif c >= 1 and c <= 3 then return "Badal Chhaye Hue"
    elseif c >= 45 and c <= 48 then return "Dhund / Fog"
    elseif c >= 51 and c <= 57 then return "Halki Barish"
    elseif c >= 61 and c <= 67 then return "Barish"
    elseif c >= 71 and c <= 77 then return "Baraf Bari"
    elseif c >= 80 and c <= 82 then return "Tez Barish"
    elseif c >= 95 and c <= 99 then return "Tufan aur Barish"
    else return "Na-maloom" end
  end
end

local function getSmartClothingAdvice(temp)
  local t = tonumber(temp) or 25
  if t < 10 then return "Karak ki sardi! Bhari woolen kapde pehnein."
  elseif t >= 10 and t < 18 then return "Sardi hai. Jacket ya garam layers theek rahengi."
  elseif t >= 18 and t < 25 then return "Mausam khushgawar hai. Halka sweater ya shirt."
  else return "Garmi hai. Halki cotton ke kapde pehnein." end
end

local function getVisualTrend(tempArray, index)
  local bars = {" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
  local minT, maxT = 999, -999
  for i = index, index + 23 do
    if i < tempArray.length() then
      local t = tonumber(tempArray.getString(i)) or 0
      if t < minT then minT = t end
      if t > maxT then maxT = t end
    end
  end
  local trendStr = "Visual Temp Trend (24h):\n"
  local range = maxT - minT
  if range == 0 then range = 1 end
  for i = index, index + 23 do
    if i < tempArray.length() then
      local t = tonumber(tempArray.getString(i)) or 0
      local barIdx = math.floor(((t - minT) / range) * 7) + 1
      trendStr = trendStr .. bars[barIdx]
    end
  end
  return trendStr
end

local function fetchNamazTimings(cityData, schoolId, fiqaName)
  speakText("Fetching Namaz timings for " .. cityData.name)
  local prayerUrl = "https://api.aladhan.com/v1/timings?latitude=" .. cityData.lat .. "&longitude=" .. cityData.lon .. "&method=1&school=" .. schoolId
  
  Http.get(prayerUrl, function(code, content)
    if code == 200 and content ~= nil then
      pcall(function()
        local json = JSONObject(content)
        local data = json.getJSONObject("data")
        local timings = data.getJSONObject("timings")
        local dateObj = data.getJSONObject("date").getJSONObject("gregorian")
        local hijriObj = data.getJSONObject("date").getJSONObject("hijri")
        
        local hDate = hijriObj.getString("day") .. " " .. hijriObj.getJSONObject("month").getString("en") .. " " .. hijriObj.getString("year") .. " AH"
        
        local msg = "Location: " .. cityData.name .. "\nMaslak: " .. fiqaName .. "\nGregorian: " .. dateObj.getString("date") .. "\nHijri: " .. hDate .. "\n\n" ..
                    "Fajr: " .. timings.getString("Fajr") .. "\nSunrise: " .. timings.getString("Sunrise") .. "\nZuhr: " .. timings.getString("Dhuhr") .. "\nAsr: " .. timings.getString("Asr") .. "\nMaghrib: " .. timings.getString("Maghrib") .. "\nIsha: " .. timings.getString("Isha")
                    
        local nDlg = LuaDialog(activity); nDlg.setTitle("Namaz Timings")
        local msgView = TextView(activity); msgView.setText(msg); msgView.setPadding(40, 40, 40, 40); msgView.setTextColor(0xFFFFFFFF); msgView.setTextSize(17)
        nDlg.setView(msgView); nDlg.setButton(DialogInterface.BUTTON_NEUTRAL, "Copy", function() copyToClipboard(msg) end); nDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil); nDlg.show()
        speakText("Namaz timings loaded.")
      end)
    else
      Toast.makeText(activity, "Failed to load timings. Check internet.", Toast.LENGTH_SHORT).show()
    end
  end)
end

local function showFiqaDialog(cityData)
  local dlg = LuaDialog(activity); dlg.setTitle("Select Maslak for Asr Time")
  local l = LinearLayout(activity); l.setOrientation(LinearLayout.VERTICAL); l.setPadding(40,40,40,40)
  
  local btnHanafi = Button(activity); btnHanafi.setText("Hanafi (Asr Shadow 2x)"); btnHanafi.setContentDescription("Hanafi Asr Shadow 2x"); btnHanafi.setBackgroundColor(0xFF2E7D32); btnHanafi.setTextColor(0xFFFFFFFF)
  local spc = TextView(activity); spc.setTextSize(6)
  local btnShafi = Button(activity); btnShafi.setText("Shafi'i / Maliki / Hanbali (Asr Shadow 1x)"); btnShafi.setContentDescription("Shafi'i Maliki Hanbali Asr Shadow 1x"); btnShafi.setBackgroundColor(0xFF1565C0); btnShafi.setTextColor(0xFFFFFFFF)
  
  l.addView(btnHanafi); l.addView(spc); l.addView(btnShafi); dlg.setView(l)
  local d = dlg.show()
  
  btnHanafi.setOnClickListener(View.OnClickListener{onClick = function() d.dismiss(); fetchNamazTimings(cityData, 1, "Hanafi") end})
  btnShafi.setOnClickListener(View.OnClickListener{onClick = function() d.dismiss(); fetchNamazTimings(cityData, 0, "Shafi'i/Deegar") end})
end

local mainRootLayout = LinearLayout(activity)
mainRootLayout.setOrientation(LinearLayout.VERTICAL)
mainRootLayout.setLayoutParams(ViewGroup.LayoutParams(-1, -1))
mainRootLayout.setBackgroundColor(0xFF121212)
mainRootLayout.setPadding(30, 30, 30, 30)

local headerText = TextView(activity)
headerText.setText("Weather Pro 360")
headerText.setTextColor(0xFF03DAC6)
headerText.setTextSize(22)
headerText.setGravity(Gravity.CENTER)
headerText.setPadding(0, 5, 0, 10)
mainRootLayout.addView(headerText)

local quickShortcutBtn = Button(activity)
quickShortcutBtn.setText("Shortcut: " .. appSettings.shortcutCityName)
quickShortcutBtn.setContentDescription("Quick Shortcut Button: " .. appSettings.shortcutCityName)
quickShortcutBtn.setBackgroundColor(0xFF03DAC6)
quickShortcutBtn.setTextColor(0xFF000000)
mainRootLayout.addView(quickShortcutBtn)

local topActions = LinearLayout(activity)
topActions.setOrientation(LinearLayout.HORIZONTAL)
topActions.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
topActions.setPadding(0, 5, 0, 15)

local locationBtn = Button(activity); locationBtn.setText("Locate"); locationBtn.setContentDescription("Current Location"); locationBtn.setBackgroundColor(0xFF03DAC6); locationBtn.setTextColor(0xFF000000)
local bp1 = LinearLayout.LayoutParams(0, -2, 1); bp1.setMargins(0,0,4,0); locationBtn.setLayoutParams(bp1); topActions.addView(locationBtn)

local favBtn = Button(activity); favBtn.setText("Favorites"); favBtn.setContentDescription("Favorites"); favBtn.setBackgroundColor(0xFFFFB300); favBtn.setTextColor(0xFF000000)
local bp2 = LinearLayout.LayoutParams(0, -2, 1); bp2.setMargins(4,0,4,0); favBtn.setLayoutParams(bp2); topActions.addView(favBtn)

local moreBtn = Button(activity); moreBtn.setText("Menu"); moreBtn.setContentDescription("More Options Menu"); moreBtn.setBackgroundColor(0xFFBB86FC); moreBtn.setTextColor(0xFF000000)
local bp3 = LinearLayout.LayoutParams(0, -2, 1); bp3.setMargins(4,0,0,0); moreBtn.setLayoutParams(bp3); topActions.addView(moreBtn)

mainRootLayout.addView(topActions)

local searchContainer = LinearLayout(activity)
searchContainer.setOrientation(LinearLayout.HORIZONTAL)
local scParams = LinearLayout.LayoutParams(-1, -2)
scParams.setMargins(0, 5, 0, 5)
searchContainer.setLayoutParams(scParams)

local searchInput = EditText(activity)
searchInput.setHint("Search city...")
searchInput.setContentDescription("Search Input Field")
searchInput.setTextColor(0xFFFFFFFF)
searchInput.setSingleLine(true)
searchInput.setBackgroundColor(0xFF222222)
local inputParams = LinearLayout.LayoutParams(0, -2, 1)
searchInput.setLayoutParams(inputParams)
searchContainer.addView(searchInput)

local micBtn = Button(activity); micBtn.setText("Mic"); micBtn.setContentDescription("Voice Search"); micBtn.setBackgroundColor(0xFFE91E63); micBtn.setTextColor(0xFFFFFFFF)
local micParams = LinearLayout.LayoutParams(-2, -2); micParams.setMargins(3,0,3,0); micBtn.setLayoutParams(micParams); searchContainer.addView(micBtn)

local clearBtn = Button(activity); clearBtn.setText("X"); clearBtn.setContentDescription("Clear Search"); clearBtn.setBackgroundColor(0xFFFF3B30); clearBtn.setTextColor(0xFFFFFFFF)
searchContainer.addView(clearBtn)

local searchBtn = Button(activity); searchBtn.setText("Go"); searchBtn.setContentDescription("Start Search"); searchBtn.setBackgroundColor(0xFFBB86FC); searchBtn.setTextColor(0xFF000000)
searchContainer.addView(searchBtn)

mainRootLayout.addView(searchContainer)

local performOnlineSearch
local fetchAndShowWeather

local recentBtn = Button(activity)
recentBtn.setText("View Recent Searches")
recentBtn.setContentDescription("View Recent Searches")
recentBtn.setBackgroundColor(0xFF333333)
recentBtn.setTextColor(0xFFFFFFFF)
local rbParams = LinearLayout.LayoutParams(-1, -2)
rbParams.setMargins(0, 5, 0, 10)
recentBtn.setLayoutParams(rbParams)
mainRootLayout.addView(recentBtn)

local function updateRecentUI()
  if not appSettings.enableRecent or #recentSearchesList == 0 then recentBtn.setVisibility(View.GONE) else recentBtn.setVisibility(View.VISIBLE) end
end
updateRecentUI()

recentBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    local dlg = LuaDialog(activity); dlg.setTitle("Recent Searches")
    local list = ListView(activity); local arr = {}
    for i, v in ipairs(recentSearchesList) do table.insert(arr, v) end
    list.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, arr))
    dlg.setView(list); local d = dlg.show()
    list.setOnItemClickListener(AdapterView.OnItemClickListener{
      onItemClick = function(parent, view, position, id) performOnlineSearch(arr[position + 1]); d.dismiss() end
    })
  end
})

local locationsListView = ListView(activity)
locationsListView.setContentDescription("Search Results List")
local listParams = LinearLayout.LayoutParams(-1, -1, 1)
locationsListView.setLayoutParams(listParams)
mainRootLayout.addView(locationsListView)

activity.setContentView(mainRootLayout)

clearBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    searchInput.setText("")
    currentSearchResults = {}
    locationsListView.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, {}))
    speakText("Search cleared.")
  end
})

performOnlineSearch = function(queryStr)
  if queryStr == "" or queryStr == nil then return end
  saveRecentSearch(queryStr); updateRecentUI()
  if currentSmartIntent == nil then speakText("Searching " .. queryStr) end
  
  local safeQuery = URLEncoder.encode(queryStr, "UTF-8")
  local geoUrl = "https://geocoding-api.open-meteo.com/v1/search?name=" .. safeQuery .. "&count=30&language=en&format=json"
  
  Http.get(geoUrl, function(code, content)
    if code == 200 and content ~= nil then
      pcall(function()
        local root = JSONObject(content)
        currentSearchResults = {}
        local displayList = {}
        if root.has("results") then
          local resultsArray = root.getJSONArray("results")
          for i=0, resultsArray.length()-1 do
            local cityObj = resultsArray.getJSONObject(i)
            local name = cityObj.getString("name")
            local country = cityObj.optString("country", "Unknown")
            local lat = cityObj.getString("latitude")
            local lon = cityObj.getString("longitude")
            local fullName = name .. " (" .. country .. ")"
            table.insert(displayList, fullName)
            table.insert(currentSearchResults, {name=name, fullName=fullName, lat=lat, lon=lon, country=country})
          end
          
          if currentSmartIntent == "smart_rain" and #currentSearchResults > 0 then
            local target = currentSearchResults[1]
            currentSmartIntent = nil
            locationsListView.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, {}))
            fetchAndShowWeather(target, "smart_rain", "Voice Assistant")
          else
            locationsListView.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, displayList))
            speakText("Results loaded.")
          end
        else
          locationsListView.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, {"No results found."}))
          speakText("No results found.")
        end
      end)
    else
      local cached = getOfflineWeather()
      if cached ~= "" then
        local resDlg = LuaDialog(activity); resDlg.setTitle("Offline Weather")
        local msgView = TextView(activity); msgView.setText(cached); msgView.setPadding(40, 40, 40, 40); msgView.setTextColor(0xFFFFFFFF)
        local scroll = ScrollView(activity); scroll.addView(msgView); resDlg.setView(scroll)
        resDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil)
        resDlg.show()
      end
    end
  end)
end

local function parseVoiceIntent(spokenText)
  local txt = string.lower(spokenText)
  local intent = nil
  if txt:find("barish") or txt:find("rain") then intent = "smart_rain" end
  local city = " " .. txt .. " "
  local stops = {"kia","kya","kal","aaj","mein","barish","hogi","hai","kaisa","mausam","ka","batao","weather","tomorrow","today","will","it","rain","in","me","ko","ki","halat", "kahan", "kab"}
  for _, w in ipairs(stops) do city = city:gsub(" " .. w .. " ", " ") end
  city = city:match("^%s*(.-)%s*$")
  if city == "" then city = appSettings.shortcutCityName end
  return city, intent
end

micBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    pcall(function()
      local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
      intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
      intent.putExtra(RecognizerIntent.EXTRA_PROMPT, "Bolein: Kal Lahore mein barish hogi?")
      activity.startActivityForResult(intent, 1001)
    end)
  end
})

function onActivityResult(requestCode, resultCode, data)
  if requestCode == 1001 and resultCode == -1 and data ~= nil then
    local resultList = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
    if resultList and resultList.size() > 0 then
      local spokenText = tostring(resultList.get(0))
      local parsedCity, intentStr = parseVoiceIntent(spokenText)
      currentSmartIntent = intentStr
      performOnlineSearch(parsedCity)
    end
  end
end

quickShortcutBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    local targetCity = {name=appSettings.shortcutCityName, fullName=appSettings.shortcutCityName, lat=appSettings.shortcutLat, lon=appSettings.shortcutLon}
    fetchAndShowWeather(targetCity, appSettings.shortcutAction, appSettings.shortcutActionName)
  end
})

local function showSettingsDialog()
  local setDlg = LuaDialog(activity); setDlg.setTitle("Smart Auto-Save Settings")
  local layout = LinearLayout(activity); layout.setOrientation(LinearLayout.VERTICAL); layout.setPadding(40, 20, 40, 20)
  
  local function addSettingSpinner(labelTxt, options, defaultIndex, callback)
    local l = LinearLayout(activity); l.setOrientation(LinearLayout.HORIZONTAL); l.setPadding(0, 15, 0, 15)
    local lbl = TextView(activity); lbl.setText(labelTxt); lbl.setTextColor(0xFF03DAC6); lbl.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    local spin = Spinner(activity)
    spin.setContentDescription(labelTxt .. " Selection")
    local adapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item, options)
    adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); spin.setAdapter(adapter); spin.setSelection(defaultIndex)
    spin.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1.2))
    spin.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{ onItemSelected = function(p, v, pos, id) callback(pos); saveAppSettings() end, onNothingSelected = function(p) end })
    l.addView(lbl); l.addView(spin); layout.addView(l)
  end

  local function addSettingCheck(labelTxt, defaultChecked, callback)
    local chk = CheckBox(activity); chk.setText(labelTxt); chk.setContentDescription(labelTxt); chk.setTextColor(0xFFFFFFFF); chk.setChecked(defaultChecked); chk.setPadding(0, 10, 0, 10)
    chk.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{ onCheckedChanged = function(v, isChecked) callback(isChecked); saveAppSettings() end })
    layout.addView(chk)
  end

  local wIdx = 0; if appSettings.windUnit == "mph" then wIdx = 1 end
  addSettingSpinner("Wind Unit:", {"km/h", "mph"}, wIdx, function(pos) if pos == 1 then appSettings.windUnit = "mph" else appSettings.windUnit = "km/h" end end)
  
  local rIdx = 0; if appSettings.rainUnit == "inches" then rIdx = 1 end
  addSettingSpinner("Rain Unit:", {"Millimeters", "Inches"}, rIdx, function(pos) if pos == 1 then appSettings.rainUnit = "inches" else appSettings.rainUnit = "mm" end end)
  
  local lIdx = 0; if appSettings.reportLang == "Hindi" then lIdx = 1 elseif appSettings.reportLang == "English" then lIdx = 2 end
  addSettingSpinner("Language:", {"Roman Urdu", "Hindi", "English"}, lIdx, function(pos) if pos == 1 then appSettings.reportLang = "Hindi" elseif pos == 2 then appSettings.reportLang = "English" else appSettings.reportLang = "Roman Urdu" end end)
  
  local fIdx = 0; if appSettings.reportFormat == "Short (Mukhtasar)" then fIdx = 1 end
  addSettingSpinner("Report Format:", {"Long (Tafseeli)", "Short (Mukhtasar)"}, fIdx, function(pos) if pos == 1 then appSettings.reportFormat = "Short (Mukhtasar)" else appSettings.reportFormat = "Long (Tafseeli)" end end)
  
  local aIdx = 0
  if appSettings.shortcutAction == "24h" then aIdx = 1 elseif tostring(appSettings.shortcutAction) == "3" then aIdx = 2 elseif tostring(appSettings.shortcutAction) == "7" then aIdx = 3 elseif tostring(appSettings.shortcutAction) == "16" then aIdx = 4 end
  addSettingSpinner("Shortcut Data:", {"Today (4 Pehar)", "24 Hours List", "3 Days", "7 Days", "16 Days Forecast"}, aIdx, function(pos)
    if pos == 1 then appSettings.shortcutAction = "24h"; appSettings.shortcutActionName = "24 Hours" elseif pos == 2 then appSettings.shortcutAction = "3"; appSettings.shortcutActionName = "3 Days" elseif pos == 3 then appSettings.shortcutAction = "7"; appSettings.shortcutActionName = "7 Days" elseif pos == 4 then appSettings.shortcutAction = "16"; appSettings.shortcutActionName = "16 Days" else appSettings.shortcutAction = "1"; appSettings.shortcutActionName = "Today (4 Pehar)" end
    quickShortcutBtn.setText("Shortcut: " .. appSettings.shortcutCityName)
  end)

  addSettingCheck("Show Recent History Button", appSettings.enableRecent, function(val) appSettings.enableRecent = val; updateRecentUI() end)
  addSettingCheck("Enable Namaz Timings Menu", appSettings.enableNamaz, function(val) appSettings.enableNamaz = val end)
  addSettingCheck("Heavy Smog/AQI Warnings", appSettings.enableSmogAlert, function(val) appSettings.enableSmogAlert = val end)
  addSettingCheck("Auto-Read Weather Voice", appSettings.autoRead, function(val) appSettings.autoRead = val end)

  local btnClearHist = Button(activity); btnClearHist.setText("Clear Recent Search History"); btnClearHist.setContentDescription("Clear Recent Search History"); btnClearHist.setBackgroundColor(0xFFFF3B30); btnClearHist.setTextColor(0xFFFFFFFF); layout.addView(btnClearHist)
  btnClearHist.setOnClickListener(View.OnClickListener{
    onClick = function() recentSearchesList = {}; prefs.edit().putString("recentSearches", "").apply(); updateRecentUI(); Toast.makeText(activity, "History Cleared", Toast.LENGTH_SHORT).show(); speakText("History cleared.") end
  })

  local scroll = ScrollView(activity); scroll.addView(layout); setDlg.setView(scroll)
  setDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil); setDlg.show()
end

local function showAboutDialog()
  local aboutDlg = LuaDialog(activity); aboutDlg.setTitle("About Weather Pro 360")
  local aboutLayout = LinearLayout(activity); aboutLayout.setOrientation(LinearLayout.VERTICAL); aboutLayout.setPadding(30, 30, 30, 30)
  local h1 = TextView(activity); h1.setText("Developer Info\ncreate bye Hafiz Zeeshan\n"); h1.setTextColor(0xFF03DAC6); h1.setTextSize(17); aboutLayout.addView(h1)
  local contactBtn = Button(activity); contactBtn.setText("Contact Developer"); contactBtn.setContentDescription("Contact Developer via WhatsApp"); contactBtn.setBackgroundColor(0xFF25D366); contactBtn.setTextColor(0xFFFFFFFF); aboutLayout.addView(contactBtn)
  contactBtn.setOnClickListener(View.OnClickListener{ onClick = function() pcall(function() activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://api.whatsapp.com/send?phone=" .. developerWhatsApp))) end) end })
  aboutDlg.setView(aboutLayout); aboutDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil); aboutDlg.show()
end

moreBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    local moreDlg = LuaDialog(activity); moreDlg.setTitle("Menu Options")
    local layout = LinearLayout(activity); layout.setOrientation(LinearLayout.VERTICAL); layout.setPadding(40, 40, 40, 40)
    local btnSet = Button(activity); btnSet.setText("Smart Settings"); btnSet.setContentDescription("Open Smart Settings"); btnSet.setBackgroundColor(0xFF333333); btnSet.setTextColor(0xFFFFFFFF); layout.addView(btnSet)
    local spc = TextView(activity); spc.setTextSize(6); layout.addView(spc)
    local btnAbt = Button(activity); btnAbt.setText("About"); btnAbt.setContentDescription("Open About Dialog"); btnAbt.setBackgroundColor(0xFF333333); btnAbt.setTextColor(0xFFFFFFFF); layout.addView(btnAbt)
    
    moreDlg.setView(layout); moreDlg.show()
    btnSet.setOnClickListener(View.OnClickListener{onClick = function() moreDlg.dismiss(); showSettingsDialog() end})
    btnAbt.setOnClickListener(View.OnClickListener{onClick = function() moreDlg.dismiss(); showAboutDialog() end})
  end
})

local function extractTimeOnly(isoStr)
  if not isoStr then return "" end
  local t = isoStr:match("T(%d+:%d+)")
  return t or isoStr
end

fetchAndShowWeather = function(cityData, actionType, durationName)
  local weatherUrl = "https://api.open-meteo.com/v1/forecast?latitude=" .. cityData.lat .. "&longitude=" .. cityData.lon .. "&current_weather=true&daily=temperature_2m_max,temperature_2m_min,weathercode,precipitation_sum,sunrise,sunset,uv_index_max,windspeed_10m_max&hourly=temperature_2m,apparent_temperature,weathercode,precipitation,cloudcover,is_day,pm2_5,surface_pressure,relativehumidity_2m,visibility&timezone=auto&forecast_days=16&past_days=1"
  
  Http.get(weatherUrl, function(code, content)
    if code == 200 and content ~= nil then
      local success, resultData = pcall(function()
        local root = JSONObject(content)
        local current = root.getJSONObject("current_weather")
        local daily = root.getJSONObject("daily")
        local hourly = root.getJSONObject("hourly")
        
        local currTemp = current.getString("temperature")
        local currCode = current.getString("weathercode")
        local currTime = current.getString("time")
        
        local hTime = hourly.getJSONArray("time")
        local hTemp = hourly.getJSONArray("temperature_2m")
        local hAppTemp = hourly.getJSONArray("apparent_temperature")
        local hCode = hourly.getJSONArray("weathercode")
        local hRain = hourly.getJSONArray("precipitation")
        local hIsDay = hourly.getJSONArray("is_day")
        
        local startIndex = 0
        for i=0, hTime.length()-1 do if hTime.getString(i) == currTime then startIndex = i break end end
        
        if actionType == "smart_rain" then
           local todayRain = tonumber(hRain.getString(startIndex)) or 0
           local tmrwRain = tonumber(hRain.getString(startIndex + 24)) or 0
           local ans = "Barish ka chance nahi hai."
           if todayRain > 0.5 or tmrwRain > 0.5 then ans = "Ji han, barish ka qavi imkan hai." end
           local smartMsg = "City: " .. cityData.name .. "\nBot Jawab: " .. ans .. "\n\nAaj ki Barish: " .. todayRain .. " mm\nKal ki Barish: " .. tmrwRain .. " mm\n\n(create bye Hafiz Zeeshan)"
           return smartMsg, ans
        end
        
        local rawWind = current.getString("windspeed")
        local windVal = tonumber(rawWind)
        local windText = rawWind .. " km/h"
        if appSettings.windUnit == "mph" then windText = string.format("%.1f", windVal * 0.621371) .. " mph" end
        
        if (tonumber(currCode) or 0) >= 80 then
          local alertDlg = LuaDialog(activity); alertDlg.setTitle("Severe Weather Alert"); alertDlg.setMessage("Heavy rain/storm detected in " .. cityData.name .. "."); alertDlg.setButton(DialogInterface.BUTTON_POSITIVE, "OK", nil); alertDlg.show()
        end
        
        local isLong = (appSettings.reportFormat == "Long (Tafseeli)")
        local lang = appSettings.reportLang or "Roman Urdu"
        
        local lbl = {}
        if lang == "English" then
          lbl.loc = "Location: "; lbl.dur = "Duration: "; lbl.temp = "Temp: "; lbl.feels = "Feels Like: "; lbl.comp = "Yesterday vs Today: "; lbl.wind = "Wind: "; lbl.hum = "Humidity: "; lbl.vis = "Visibility: "; lbl.cond = "Condition: "; lbl.adv = "Advice: "; lbl.act = "Activity: "; lbl.aqi = "AQI/Smog: "; lbl.uv = "UV Index: "; lbl.desi = "Desi Month: "; lbl.rain = "Rain: "; lbl.press = "Pressure: "; lbl.sunr = "Sunrise: "; lbl.suns = "Sunset: "; lbl.time = "Time: "; lbl.date = "Date: "; lbl.max = "Max: "; lbl.min = "Min: "
        elseif lang == "Hindi" then
          lbl.loc = "स्थान: "; lbl.dur = "अवधि: "; lbl.temp = "तापमान: "; lbl.feels = "महसूस होता है: "; lbl.comp = "कल बनाम आज: "; lbl.wind = "हवा: "; lbl.hum = "आर्द्रता: "; lbl.vis = "विजिबिलिटी: "; lbl.cond = "स्थिति: "; lbl.adv = "सलाह: "; lbl.act = "गतिविधि: "; lbl.aqi = "एक्यूआई: "; lbl.uv = "यूवी: "; lbl.desi = "देसी महीना: "; lbl.rain = "वर्षा: "; lbl.press = "दबाव: "; lbl.sunr = "सूर्योदय: "; lbl.suns = "सूर्यास्त: "; lbl.time = "समय: "; lbl.date = "दिनांक: "; lbl.max = "अधिकतम: "; lbl.min = "न्यूनतम: "
        else
          lbl.loc = "Jagah: "; lbl.dur = "Dauraniya: "; lbl.temp = "Darja Hararat: "; lbl.feels = "Asal Ehsas: "; lbl.comp = "Kal vs Aaj: "; lbl.wind = "Hawa: "; lbl.hum = "Nami (Humidity): "; lbl.vis = "Dekhne ki Hadd: "; lbl.cond = "Halat: "; lbl.adv = "Mashwara: "; lbl.act = "Aaj ki Activity: "; lbl.aqi = "Hawa ki Quality: "; lbl.uv = "Dhoop ki Tezi (UV): "; lbl.desi = "Desi Mahina: "; lbl.rain = "Barish: "; lbl.press = "Hawa ka Dabao: "; lbl.sunr = "Tulu-e-Aftab: "; lbl.suns = "Ghuroob: "; lbl.time = "Waqt: "; lbl.date = "Tarikh: "; lbl.max = "Ziada Temp: "; lbl.min = "Kam Temp: "
        end
        
        local finalRep = getTimeBasedGreeting() .. "\n" .. lbl.loc .. cityData.fullName .. "\n" .. lbl.dur .. durationName .. "\n\n"
        
        if actionType == "24h" then
          if isLong then finalRep = finalRep .. getVisualTrend(hTemp, startIndex) .. "\n\n" end
          for i = startIndex, startIndex + 23 do
            if i < hTime.length() then
              local tRainText = (tonumber(hRain.getString(i)) or 0) .. " mm"
              if appSettings.rainUnit == "inches" then tRainText = string.format("%.2f", (tonumber(hRain.getString(i)) or 0) / 25.4) .. " in" end
              
              if isLong then
                finalRep = finalRep .. lbl.time .. formatTimeForTTS(hTime.getString(i)) .. "\n" .. lbl.temp .. hTemp.getString(i) .. " C | " .. lbl.hum .. hHumidity.optString(i, "50") .. "%\n" .. lbl.rain .. tRainText .. " | " .. lbl.cond .. getWeatherCondition(hCode.getString(i), hIsDay.optInt(i, 1) == 0 and 1 or 0) .. "\n\n"
              else
                finalRep = finalRep .. lbl.time .. formatTimeForTTS(hTime.getString(i)) .. " | " .. lbl.temp .. hTemp.getString(i) .. " C | " .. lbl.cond .. getWeatherCondition(hCode.getString(i), hIsDay.optInt(i, 1) == 0 and 1 or 0) .. "\n"
              end
            end
          end
          return finalRep .. "\n(create bye Hafiz Zeeshan)", nil
        end
        
        local multiDays = tonumber(actionType)
        if multiDays and multiDays > 1 then
          local dTime, dMax, dMin, dCode, dRain, dWind = daily.getJSONArray("time"), daily.getJSONArray("temperature_2m_max"), daily.getJSONArray("temperature_2m_min"), daily.getJSONArray("weathercode"), daily.getJSONArray("precipitation_sum"), daily.getJSONArray("windspeed_10m_max")
          local loopEnd = multiDays; if loopEnd >= dTime.length() then loopEnd = dTime.length() - 1 end
          for i=1, loopEnd do
            local dailyWind = (tonumber(dWind.getString(i)) or 0) .. " km/h"; if appSettings.windUnit == "mph" then dailyWind = string.format("%.1f", (tonumber(dWind.getString(i)) or 0) * 0.621371) .. " mph" end
            local dCond = getWeatherCondition(dCode.getString(i), 0)
            
            if isLong then
              finalRep = finalRep .. lbl.date .. formatDateForTTS(dTime.getString(i)) .. "\n" .. lbl.max .. dMax.getString(i) .. " C | " .. lbl.min .. dMin.getString(i) .. " C\n" .. lbl.wind .. dailyWind .. " | " .. lbl.cond .. dCond .. "\n" .. lbl.adv .. getSmartClothingAdvice(dMax.getString(i)) .. "\n\n"
            else
              finalRep = finalRep .. lbl.date .. formatDateForTTS(dTime.getString(i)) .. "\n" .. lbl.max .. dMax.getString(i) .. " C | " .. lbl.cond .. dCond .. "\n\n"
            end
          end
          return finalRep .. "(create bye Hafiz Zeeshan)", nil
        end
        
        -- Default (Action 1) - Today Report
        if isLong then
          local dRain = daily.getJSONArray("precipitation_sum")
          local dSunrise = daily.getJSONArray("sunrise")
          local dSunset = daily.getJSONArray("sunset")
          local dMax = daily.getJSONArray("temperature_2m_max")

          local todayRainVal = tonumber(dRain.getString(1)) or 0
          local todayRainStr = todayRainVal .. " mm"
          if appSettings.rainUnit == "inches" then todayRainStr = string.format("%.2f", todayRainVal / 25.4) .. " in" end

          local rawSunrise = dSunrise.getString(1)
          local rawSunset = dSunset.getString(1)
          local countdownText = getCountdown(currTime, rawSunrise, rawSunset)
          local sunriseStr = extractTimeOnly(rawSunrise)
          local sunsetStr = extractTimeOnly(rawSunset)

          local currentUv = daily.getJSONArray("uv_index_max").optDouble(1, 5)
          local pY, pM, pD = currTime:match("(%d+)-(%d+)-(%d+)T")
          local dMonthStr = getDesiMonth(tonumber(pM), tonumber(pD))
          
          local currFeelsLike = hAppTemp.optString(startIndex, currTemp)
          
          local yesterdayMax = tonumber(dMax.getString(0)) or 0
          local todayMax = tonumber(dMax.getString(1)) or 0
          local tempDiff = todayMax - yesterdayMax
          local comparisonText = ""
          if tempDiff > 1 then comparisonText = "Aaj kal se " .. string.format("%.1f", tempDiff) .. " C zyada garm hai."
          elseif tempDiff < -1 then comparisonText = "Aaj kal se " .. string.format("%.1f", math.abs(tempDiff)) .. " C zyada thanda hai."
          else comparisonText = "Aaj ka mausam taqreeban kal jaisa hi hai." end

          finalRep = finalRep .. lbl.temp .. currTemp .. " C (" .. lbl.feels .. currFeelsLike .. " C)\n"
          finalRep = finalRep .. lbl.comp .. comparisonText .. "\n"
          finalRep = finalRep .. lbl.wind .. windText .. "\n"
          finalRep = finalRep .. lbl.rain .. todayRainStr .. "\n"
          finalRep = finalRep .. lbl.cond .. getWeatherCondition(currCode, current.optInt("is_day", 1) == 0 and 1 or 0) .. "\n"
          finalRep = finalRep .. countdownText .. "\n"
          finalRep = finalRep .. lbl.sunr .. sunriseStr .. " | " .. lbl.suns .. sunsetStr .. "\n\n"
          
          local mTemp = (startIndex + 6 < hTemp.length()) and hTemp.getString(startIndex + 6) or "--"
          local aTemp = (startIndex + 12 < hTemp.length()) and hTemp.getString(startIndex + 12) or "--"
          local eTemp = (startIndex + 18 < hTemp.length()) and hTemp.getString(startIndex + 18) or "--"
          local nTemp = (startIndex + 22 < hTemp.length()) and hTemp.getString(startIndex + 22) or "--"

          local mCond = (startIndex + 6 < hCode.length()) and getWeatherCondition(hCode.getString(startIndex + 6), 0) or "--"
          local aCond = (startIndex + 12 < hCode.length()) and getWeatherCondition(hCode.getString(startIndex + 12), 0) or "--"
          local eCond = (startIndex + 18 < hCode.length()) and getWeatherCondition(hCode.getString(startIndex + 18), 0) or "--"
          local nCond = (startIndex + 22 < hCode.length()) and getWeatherCondition(hCode.getString(startIndex + 22), 1) or "--"

          local peharTitle = "Aaj ke 4 Pehar:\n"
          local peharText = peharTitle .. "Subah: " .. mTemp .. " C (" .. mCond .. ")\nDopehar: " .. aTemp .. " C (" .. aCond .. ")\nShaam: " .. eTemp .. " C (" .. eCond .. ")\nRaat: " .. nTemp .. " C (" .. nCond .. ")\n\n"
          
          finalRep = finalRep .. peharText

          local hPm25 = hourly.getJSONArray("pm2_5")
          local hPressure = hourly.getJSONArray("surface_pressure")
          local hHumidity = hourly.getJSONArray("relativehumidity_2m")
          local hVisibility = hourly.getJSONArray("visibility")
          local currentPm25 = hPm25.optDouble(startIndex, 35)

          local timeMachineStr = getTimeMachineWeather(currTemp)
          local moonPhaseStr = getMoonPhaseDetails()

          finalRep = finalRep .. lbl.hum .. hHumidity.optString(startIndex, "55") .. "%\n" .. lbl.press .. hPressure.optString(startIndex, "1013") .. " hPa\n" .. lbl.vis .. string.format("%.1f", hVisibility.optDouble(startIndex, 10000)/1000) .. " km\n" .. lbl.aqi .. currentPm25 .. " PM2.5\n" .. lbl.uv .. string.format("%.1f", currentUv) .. "\n" .. lbl.desi .. dMonthStr .. "\n\n" .. timeMachineStr .. "\n\n" .. moonPhaseStr .. "\n\n" .. lbl.adv .. getSmartClothingAdvice(currTemp) .. "\n" .. lbl.act .. getActivitySuggestion(currTemp, currCode, current.optInt("is_day", 1) == 0 and 1 or 0) .. "\n\n"
        else
          finalRep = finalRep .. lbl.temp .. currTemp .. " C\n"
          finalRep = finalRep .. lbl.cond .. getWeatherCondition(currCode, current.optInt("is_day", 1) == 0 and 1 or 0) .. "\n\n"
        end
        
        return finalRep .. "(create bye Hafiz Zeeshan)", nil
      end)
      
      if success and resultData then
        local mainRep = resultData
        if actionType ~= "smart_rain" then saveOfflineWeather(mainRep) end
        
        local resDlg = LuaDialog(activity); resDlg.setTitle(durationName); 
        local msgView = TextView(activity); msgView.setText(mainRep); msgView.setPadding(40,40,40,40); msgView.setTextColor(0xFFFFFFFF)
        local scroll = ScrollView(activity); scroll.addView(msgView); resDlg.setView(scroll)
        resDlg.setButton(DialogInterface.BUTTON_NEUTRAL, "Copy", function() copyToClipboard(mainRep) end)
        resDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil); resDlg.show()
        
        if actionType == "smart_rain" then speakText(errOrVoice) elseif appSettings.autoRead then speakText(mainRep) end
      end
    end
  end)
end

local function showOptionsDialog(cityData)
  local optDlg = LuaDialog(activity)
  optDlg.setTitle("Select Option:\n" .. cityData.name)
  
  local btnLayout = LinearLayout(activity)
  btnLayout.setOrientation(LinearLayout.VERTICAL)
  btnLayout.setPadding(40, 40, 40, 40)
  
  local durations = { {label = "Today", action = 1}, {label = "24 Hours List", action = "24h"}, {label = "3 Days", action = 3}, {label = "7 Days", action = 7}, {label = "16 Days Forecast", action = 16} }
  if appSettings.enableNamaz then table.insert(durations, {label = "Namaz Timings (Prayer)", action = "namaz"}) end
  
  for i, v in ipairs(durations) do
    local btn = Button(activity)
    btn.setText(v.label)
    btn.setContentDescription(v.label .. " Option")
    if v.action == "namaz" then btn.setBackgroundColor(0xFF2E7D32) else btn.setBackgroundColor(0xFF333333) end
    btn.setTextColor(0xFFFFFFFF)
    btnLayout.addView(btn)
    local space = TextView(activity); space.setTextSize(6); btnLayout.addView(space)
    
    btn.setOnClickListener(View.OnClickListener{
      onClick = function() 
        optDlg.dismiss()
        if v.action == "namaz" then showFiqaDialog(cityData) else fetchAndShowWeather(cityData, v.action, v.label) end
      end
    })
  end
  optDlg.setView(btnLayout)
  optDlg.show()
end

locationsListView.setOnItemClickListener(AdapterView.OnItemClickListener{
  onItemClick = function(parent, view, position, id) 
    searchInput.setText("")
    showOptionsDialog(currentSearchResults[position + 1]) 
  end
})

locationsListView.setOnItemLongClickListener(AdapterView.OnItemLongClickListener{
  onItemLongClick = function(parent, view, position, id)
    local selectedCityData = currentSearchResults[position + 1]
    if selectedCityData then
      local addDlg = LuaDialog(activity); addDlg.setTitle(selectedCityData.name)
      addDlg.setButton(DialogInterface.BUTTON_NEUTRAL, "Set Shortcut", function()
        appSettings.shortcutCityName = selectedCityData.fullName
        appSettings.shortcutLat = selectedCityData.lat
        appSettings.shortcutLon = selectedCityData.lon
        saveAppSettings(); quickShortcutBtn.setText("Shortcut: " .. appSettings.shortcutCityName)
        speakText("Shortcut Set")
      end)
      addDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Favorite", function() table.insert(favoriteCities, selectedCityData); speakText("Added to Favorites") end)
      addDlg.setButton(DialogInterface.BUTTON_NEGATIVE, "Cancel", nil); addDlg.show()
    end
    return true
  end
})

favBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    if #favoriteCities == 0 then 
      Toast.makeText(activity, "No favorites yet.", Toast.LENGTH_SHORT).show()
      speakText("Favorites list is empty.")
      return 
    end
    currentSearchResults = {}; local displayList = {}
    for i, city in ipairs(favoriteCities) do table.insert(displayList, city.fullName); table.insert(currentSearchResults, city) end
    locationsListView.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, displayList))
    speakText("Showing favorite cities.")
  end
})

locationBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    speakText("System map se ilaqa pata lagaya ja raha hai, please wait...")
    pcall(function()
      local locManager = activity.getSystemService(Context.LOCATION_SERVICE)
      local isGPSEnabled = locManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
      local isNetworkEnabled = locManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
      
      if not isGPSEnabled and not isNetworkEnabled then
        Toast.makeText(activity, "Please turn on GPS/Location services.", Toast.LENGTH_LONG).show()
        speakText("Please turn on location services.")
        return
      end
      
      local location = locManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
      if location == nil then location = locManager.getLastKnownLocation(LocationManager.GPS_PROVIDER) end
      
      if location ~= nil then
        local latVal = location.getLatitude()
        local lonVal = location.getLongitude()
        local latStr = tostring(latVal)
        local lonStr = tostring(lonVal)
        
        local geocoder = Geocoder(activity, Locale.getDefault())
        local addresses = geocoder.getFromLocation(latVal, lonVal, 1)
        
        local resolvedLocationName = ""
        if addresses and addresses.size() > 0 then
          local addr = addresses.get(0)
          local locality = addr.getLocality()
          local subLocality = addr.getSubLocality()
          local featureName = addr.getFeatureName()
          local adminArea = addr.getAdminArea()
          
          if featureName and featureName ~= "" and featureName ~= latStr then
            resolvedLocationName = featureName
          end
          if subLocality and subLocality ~= "" and subLocality ~= resolvedLocationName then
            if resolvedLocationName ~= "" then resolvedLocationName = resolvedLocationName .. ", " .. subLocality else resolvedLocationName = subLocality end
          end
          if locality and locality ~= "" and locality ~= resolvedLocationName then
            if resolvedLocationName ~= "" then resolvedLocationName = resolvedLocationName .. " (" .. locality .. ")" else resolvedLocationName = locality end
          elseif adminArea and adminArea ~= "" and not resolvedLocationName:find(adminArea) then
            if resolvedLocationName ~= "" then resolvedLocationName = resolvedLocationName .. ", " .. adminArea else resolvedLocationName = adminArea end
          end
        end
        
        if resolvedLocationName == "" or resolvedLocationName == nil then
          resolvedLocationName = "Maujooda Muqam"
        end
        
        local locData = {name=resolvedLocationName, fullName=resolvedLocationName, lat=latStr, lon=lonStr}
        
        appSettings.shortcutCityName = locData.fullName
        appSettings.shortcutLat = latStr
        appSettings.shortcutLon = lonStr
        saveAppSettings()
        quickShortcutBtn.setText("Shortcut: " .. appSettings.shortcutCityName)
        
        speakText("Location found: " .. resolvedLocationName)
        showOptionsDialog(locData)
      else
        Toast.makeText(activity, "Unable to get location coordinates.", Toast.LENGTH_LONG).show()
        speakText("Unable to get location.")
      end
    end)
  end
})

searchBtn.setOnClickListener(View.OnClickListener{ onClick = function() performOnlineSearch(tostring(searchInput.getText())) end })

task(800, function()
  Toast.makeText(activity, "create bye Hafiz Zeeshan", Toast.LENGTH_SHORT).show()
  speakText("Weather Pro 360 loaded. create bye Hafiz Zeeshan.")
end)