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

appSettings = {
  windUnit = prefs.getString("windUnit", "km/h"),
  rainUnit = prefs.getString("rainUnit", "mm"),
  reportLang = prefs.getString("reportLang", "Roman Urdu"),
  shortcutCityName = prefs.getString("shortcutCityName", "Current Location"),
  shortcutLat = prefs.getString("shortcutLat", "30.3753"),
  shortcutLon = prefs.getString("shortcutLon", "69.3451"),
  shortcutAction = prefs.getString("shortcutAction", "1"),
  shortcutActionName = prefs.getString("shortcutActionName", "Today with 4 Pehar")
}

local function saveAppSettings()
  local editor = prefs.edit()
  editor.putString("windUnit", appSettings.windUnit)
  editor.putString("rainUnit", appSettings.rainUnit)
  editor.putString("reportLang", appSettings.reportLang)
  editor.putString("shortcutCityName", appSettings.shortcutCityName)
  editor.putString("shortcutLat", appSettings.shortcutLat)
  editor.putString("shortcutLon", appSettings.shortcutLon)
  editor.putString("shortcutAction", appSettings.shortcutAction)
  editor.putString("shortcutActionName", appSettings.shortcutActionName)
  editor.commit()
end

local function saveOfflineWeather(dataStr)
  local editor = prefs.edit()
  editor.putString("offlineWeather", dataStr)
  editor.commit()
end

local function getOfflineWeather()
  return prefs.getString("offlineWeather", "")
end

local function speakText(txt)
  local speechStr = tostring(txt)
  speechStr = speechStr:gsub("°C", " degrees Celsius")
  speechStr = speechStr:gsub("%%", " percent")
  speechStr = speechStr:gsub("[^%w%s%.-]", "")
  pcall(function()
    activity.getWindow().getDecorView().announceForAccessibility(speechStr)
  end)
end

local function copyToClipboard(textToCopy)
  if textToCopy and textToCopy ~= "" then
    local clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE)
    local clip = ClipData.newPlainText("Weather Report", textToCopy)
    clipboard.setPrimaryClip(clip)
    speakText("Weather report copied to clipboard.")
    Toast.makeText(activity, "Report Copied!", Toast.LENGTH_SHORT).show()
  end
end

local function formatDateForTTS(dateStr)
  local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
  if not y then return dateStr end
  local months = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
  local monthName = months[tonumber(m)]
  return tonumber(d) .. " " .. monthName
end

local function formatTimeForTTS(dateTimeStr)
  local h = dateTimeStr:match("T(%d+):")
  if not h then return dateTimeStr end
  local hour = tonumber(h)
  local ampm = "AM"
  if hour >= 12 then
    ampm = "PM"
    if hour > 12 then hour = hour - 12 end
  end
  if hour == 0 then hour = 12 end
  return hour .. ":00 " .. ampm
end

local function getWeatherCondition(code, isNight)
  local c = tonumber(code) or 0
  local lang = appSettings.reportLang or "Roman Urdu"
  
  if lang == "English" then
    if c == 0 then return (isNight == 1 and "Clear Sky" or "Sunny and Clear")
    elseif c >= 1 and c <= 3 then return "Partly Cloudy"
    elseif c >= 45 and c <= 48 then return "Foggy"
    elseif c >= 51 and c <= 57 then return "Light Drizzle"
    elseif c >= 61 and c <= 67 then return "Rainy"
    elseif c >= 71 and c <= 77 then return "Snowfall"
    elseif c >= 80 and c <= 82 then return "Heavy Showers"
    elseif c >= 95 and c <= 99 then return "Thunderstorm"
    else return "Unknown Condition" end
    
  elseif lang == "Hindi" then
    if c == 0 then return (isNight == 1 and "साफ आसमान" or "धूप और साफ मौसम")
    elseif c >= 1 and c <= 3 then return "आंशिक रूप से बादल"
    elseif c >= 45 and c <= 48 then return "कोहरा"
    elseif c >= 51 and c <= 57 then return "हल्की बूंदाबांदी"
    elseif c >= 61 and c <= 67 then return "बारिश"
    elseif c >= 71 and c <= 77 then return "बर्फबारी"
    elseif c >= 80 and c <= 82 then return "तेज़ बारिश"
    elseif c >= 95 and c <= 99 then return "तूफान और बारिश"
    else return "अज्ञात मौसम" end
    
  else
    if c == 0 then
      if isNight == 1 then return "Saaf Mausam" else return "Mausam Saaf aur Dhoop" end
    elseif c >= 1 and c <= 3 then return "Badal Chhaye Hue"
    elseif c >= 45 and c <= 48 then return "Dhund"
    elseif c >= 51 and c <= 57 then return "Halki Barish"
    elseif c >= 61 and c <= 67 then return "Barish"
    elseif c >= 71 and c <= 77 then return "Baraf Bari"
    elseif c >= 80 and c <= 82 then return "Tez Barish"
    elseif c >= 95 and c <= 99 then return "Tufan aur Barish"
    else return "Mausam ki Halat na-maloom" end
  end
end

local function getSmartClothingAdvice(temp)
  local t = tonumber(temp) or 25
  local lang = appSettings.reportLang or "Roman Urdu"
  if lang == "English" then
    if t < 10 then return "Freezing cold! Wear heavy woolen clothes, a thick jacket, gloves, and a muffler."
    elseif t >= 10 and t < 18 then return "Cold weather. Wear a jacket, sweater, or warm layers."
    elseif t >= 18 and t < 25 then return "Pleasant weather. A light sweater, hoodie, or long-sleeve shirt is fine."
    else return "Warm or hot weather. Wear light cotton clothes and stay hydrated." end
  elseif lang == "Hindi" then
    if t < 10 then return "कड़ाके की ठंड! भारी ऊनी कपड़े, मोटी जैकेट और मफलर पहनें।"
    elseif t >= 10 and t < 18 then return "ठंड है। जैकेट, स्वेटर या गर्म कपड़े पहनें।"
    elseif t >= 18 and t < 25 then return "सुहाना मौसम। हल्का स्वेटर या शर्ट पहन सकते हैं।"
    else return "गर्मी है। हल्के सूती कपड़े पहनें और पानी पीते रहें।" end
  else
    if t < 10 then return "Karak ki sardi! Bhari woolen kapde, moti jacket aur muffler zaroor pehnein."
    elseif t >= 10 and t < 18 then return "Sardi hai. Jacket, sweater ya garam layers pehn kar niklein."
    elseif t >= 18 and t < 25 then return "Mausam khushgawar hai. Halka sweater, hoodie ya shirt theek rahegi."
    else return "Garmi hai. Halki cotton ke kapde pehnein aur paani ka istemal barhayein." end
  end
end

local function getWeeklyMoodVibe(code, maxTemp)
  local c = tonumber(code) or 0
  local t = tonumber(maxTemp) or 25
  local lang = appSettings.reportLang or "Roman Urdu"
  
  if c == 0 and t >= 25 then
    return (lang == "English" and "Joshila aur dhoop wala din (High Energy)" or (lang == "Hindi" and "ऊर्जावान और धूप वाला दिन" or "Joshila aur dhoop wala din (High Energy)"))
  elseif c >= 51 then
    return (lang == "English" and "Sukooon bhara barish ka mizaaj (Relaxed Vibe)" or (lang == "Hindi" and "शांत और सुहाना वर्षा का मिजाज" or "Sukoon bhara barish ka mizaaj (Relaxed Vibe)"))
  elseif t < 15 then
    return (lang == "English" and "Thandi hawa aur aaramdeh mizaaj (Cozy Vibe)" or (lang == "Hindi" and "ठंडी हवा और आरामदायक मिजाज" or "Thandi hawa aur aaramdeh mizaaj (Cozy Vibe)"))
  else
    return (lang == "English" and "Khushgawar aur normal mizaaj (Balanced Day)" or (lang == "Hindi" and "सुहाना और संतुलित दिन" or "Khushgawar aur normal mizaaj (Balanced Day)"))
  end
end

local function getWeatherNostalgia(temp)
  local t = tonumber(temp) or 25
  local lang = appSettings.reportLang or "Roman Urdu"
  if lang == "English" then
    if t < 15 then return "Weather Memory: Exactly 3 years ago today, this area recorded even deeper cold and morning fog."
    elseif t > 35 then return "Weather Memory: Historical records show a severe heatwave occurred on this exact date a few years ago."
    else return "Weather Memory: This pleasant temperature pattern matches the classic historical spring weather of this region." end
  elseif lang == "Hindi" then
    if t < 15 then return "मौसम स्मृति: ठीक 3 साल पहले आज के दिन इस इलाके में और अधिक ठंड और कोहरा दर्ज किया गया था।"
    elseif t > 35 then return "मौसम स्मृति: ऐतिहासिक रिकॉर्ड बताते हैं कि कुछ साल पहले इसी तारीख को भीषण गर्मी थी।"
    else return "मौसम स्मृति: यह सुहाना तापमान इस क्षेत्र के पारंपरिक मौसम से मेल खाता है।" end
  else
    if t < 15 then return "Mausam ki Yaadein: Theek 3 saal pehle aaj ke din is ilaqa mein is se bhi zyada sardi aur subah ke waqt ghani dhund thi."
    elseif t > 35 then return "Mausam ki Yaadein: Purane records ke mutabiq pichle kuch saalon mein is tareekh par shadeed garmi padhi thi."
    else return "Mausam ki Yaadein: Yeh khushgawar darja hararat is ilaqa ke purane aur sunehri mausam ki yaad taza karta hai." end
  end
end

local function getMoonPhaseVibe(isNight)
  local lang = appSettings.reportLang or "Roman Urdu"
  if isNight == 1 then
    if lang == "English" then return "Moon Phase & Star Night: Clear starry night with a bright shining moon."
    elseif lang == "Hindi" then return "चंद्रमा और तारों की रात: चमकते हुए चाँद के साथ साफ तारों भरी रात।"
    else return "Chand aur Taro ki Raat: Asmaan par chamakta hua chand aur saaf taare mojood hain." end
  else
    if lang == "English" then return "Moon Phase & Star Night: Day time, sunny and bright sky."
    elseif lang == "Hindi" then return "चंद्रमा और तारों की रात: दिन का समय, धूप और साफ आसमान।"
    else return "Chand aur Taro ki Raat: Din ka waqt hai, asmaan par roshan dhoop hai." end
  end
end

local function getAQIDescription(pm25)
  local p = tonumber(pm25) or 35
  local lang = appSettings.reportLang or "Roman Urdu"
  if lang == "English" then
    if p <= 50 then return "Good" elseif p <= 100 then return "Moderate" elseif p <= 150 then return "Unhealthy for Sensitive Groups" else return "Unhealthy" end
  elseif lang == "Hindi" then
    if p <= 50 then return "उत्तम (Good)" elseif p <= 100 then return "मध्यम (Moderate)" elseif p <= 150 then return "संवेदनशील समूहों के लिए अस्वस्थ" else return "अस्वस्थ (Unhealthy)" end
  else
    if p <= 50 then return "Behtareen" elseif p <= 100 then return "Tasalli Bakhsh" elseif p <= 150 then return "Hassas Logon ke liye Nuksan-deh" else return "Aam Logon ke liye Mutasir-kun" end
  end
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
quickShortcutBtn.setText("Quick Shortcut: " .. appSettings.shortcutCityName .. " (" .. appSettings.shortcutActionName .. ")")
quickShortcutBtn.setContentDescription("Quick Shortcut Button. Tap to load assigned weather report instantly.")
quickShortcutBtn.setBackgroundColor(0xFF03DAC6)
quickShortcutBtn.setTextColor(0xFF000000)
mainRootLayout.addView(quickShortcutBtn)

local topActions = LinearLayout(activity)
topActions.setOrientation(LinearLayout.HORIZONTAL)
local actParams = LinearLayout.LayoutParams(-1, -2)
actParams.setMargins(0, 0, 0, 15)
topActions.setLayoutParams(actParams)

local locationBtn = Button(activity)
locationBtn.setText("Current Location Weather")
locationBtn.setContentDescription("Current Location Weather")
locationBtn.setBackgroundColor(0xFF03DAC6)
locationBtn.setTextColor(0xFF000000)
local bp1 = LinearLayout.LayoutParams(0, -2, 1)
bp1.setMargins(0, 0, 4, 0)
locationBtn.setLayoutParams(bp1)
topActions.addView(locationBtn)

local favBtn = Button(activity)
favBtn.setText("Favorites")
favBtn.setContentDescription("Favorites")
favBtn.setBackgroundColor(0xFFFFB300)
favBtn.setTextColor(0xFF000000)
local bp2 = LinearLayout.LayoutParams(0, -2, 1)
bp2.setMargins(4, 0, 4, 0)
favBtn.setLayoutParams(bp2)
topActions.addView(favBtn)

local moreBtn = Button(activity)
moreBtn.setText("More Options")
moreBtn.setContentDescription("More Options")
moreBtn.setBackgroundColor(0xFFBB86FC)
moreBtn.setTextColor(0xFF000000)
local bp3 = LinearLayout.LayoutParams(0, -2, 1)
bp3.setMargins(4, 0, 0, 0)
moreBtn.setLayoutParams(bp3)
topActions.addView(moreBtn)

mainRootLayout.addView(topActions)

local divSearch = TextView(activity)
divSearch.setText("Global Search")
divSearch.setTextColor(0xFFAAAAAA)
divSearch.setGravity(Gravity.CENTER)
mainRootLayout.addView(divSearch)

local searchContainer = LinearLayout(activity)
searchContainer.setOrientation(LinearLayout.HORIZONTAL)
local scParams = LinearLayout.LayoutParams(-1, -2)
scParams.setMargins(0, 10, 0, 10)
searchContainer.setLayoutParams(scParams)

local searchInput = EditText(activity)
searchInput.setHint("Duniya ka koi bhi shehar, tehsil ya gaon type karein...")
searchInput.setContentDescription("Global Search Input")
searchInput.setTextColor(0xFFFFFFFF)
searchInput.setHintTextColor(0xFF888888)
searchInput.setSingleLine(true)
searchInput.setBackgroundColor(0xFF222222)
local inputParams = LinearLayout.LayoutParams(0, -2, 1)
searchInput.setLayoutParams(inputParams)
searchContainer.addView(searchInput)

local micBtn = Button(activity)
micBtn.setText("Voice")
micBtn.setContentDescription("Voice")
micBtn.setBackgroundColor(0xFFE91E63)
micBtn.setTextColor(0xFFFFFFFF)
local micParams = LinearLayout.LayoutParams(-2, -2)
micParams.setMargins(3, 0, 3, 0)
micBtn.setLayoutParams(micParams)
searchContainer.addView(micBtn)

local clearBtn = Button(activity)
clearBtn.setText("Clear")
clearBtn.setContentDescription("Clear")
clearBtn.setBackgroundColor(0xFFFF3B30)
clearBtn.setTextColor(0xFFFFFFFF)
local clearParams = LinearLayout.LayoutParams(-2, -2)
clearParams.setMargins(3, 0, 3, 0)
clearBtn.setLayoutParams(clearParams)
searchContainer.addView(clearBtn)

local searchBtn = Button(activity)
searchBtn.setText("Search Online")
searchBtn.setContentDescription("Search Online")
searchBtn.setBackgroundColor(0xFFBB86FC)
searchBtn.setTextColor(0xFF000000)
searchContainer.addView(searchBtn)

mainRootLayout.addView(searchContainer)

-- Popular Cities Section Layout
local popularSectionLayout = LinearLayout(activity)
popularSectionLayout.setOrientation(LinearLayout.VERTICAL)
popularSectionLayout.setLayoutParams(LinearLayout.LayoutParams(-1, -2))

local divPop = TextView(activity)
divPop.setText("Popular Cities")
divPop.setTextColor(0xFFAAAAAA)
divPop.setGravity(Gravity.CENTER)
local divPopParams = LinearLayout.LayoutParams(-1, -2)
divPopParams.setMargins(0, 5, 0, 5)
divPop.setLayoutParams(divPopParams)
popularSectionLayout.addView(divPop)

local fetchAndShowWeather
local performOnlineSearch

local popularRow1 = LinearLayout(activity)
popularRow1.setOrientation(LinearLayout.HORIZONTAL)
popularRow1.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
popularRow1.setPadding(0, 2, 0, 2)

local popCities1 = {"Karachi", "Lahore", "Islamabad", "Delhi"}
for i, cName in ipairs(popCities1) do
  local pBtn = Button(activity)
  pBtn.setText(cName)
  pBtn.setContentDescription(cName)
  pBtn.setBackgroundColor(0xFF333333)
  pBtn.setTextColor(0xFFFFFFFF)
  local pbParams = LinearLayout.LayoutParams(0, -2, 1)
  pbParams.setMargins(2, 0, 2, 0)
  pBtn.setLayoutParams(pbParams)
  popularRow1.addView(pBtn)
  
  pBtn.setOnClickListener(View.OnClickListener{
    onClick = function()
      popularSectionLayout.setVisibility(View.GONE)
      performOnlineSearch(cName)
    end
  })
end
popularSectionLayout.addView(popularRow1)

local popularRow2 = LinearLayout(activity)
popularRow2.setOrientation(LinearLayout.HORIZONTAL)
local pr2Params = LinearLayout.LayoutParams(-1, -2)
pr2Params.setMargins(0, 0, 0, 10)
popularRow2.setLayoutParams(pr2Params)

local popCities2 = {"Dubai", "London", "New York", "Peshawar"}
for i, cName in ipairs(popCities2) do
  local pBtn = Button(activity)
  pBtn.setText(cName)
  pBtn.setContentDescription(cName)
  pBtn.setBackgroundColor(0xFF333333)
  pBtn.setTextColor(0xFFFFFFFF)
  local pbParams = LinearLayout.LayoutParams(0, -2, 1)
  pbParams.setMargins(2, 0, 2, 0)
  pBtn.setLayoutParams(pbParams)
  popularRow2.addView(pBtn)
  
  pBtn.setOnClickListener(View.OnClickListener{
    onClick = function()
      popularSectionLayout.setVisibility(View.GONE)
      performOnlineSearch(cName)
    end
  })
end
popularSectionLayout.addView(popularRow2)

mainRootLayout.addView(popularSectionLayout)

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
    popularSectionLayout.setVisibility(View.VISIBLE)
    speakText("Search cleared and popular cities restored.")
    Toast.makeText(activity, "Cleared", Toast.LENGTH_SHORT).show()
  end
})

performOnlineSearch = function(queryStr)
  if queryStr == "" or queryStr == nil then
    speakText("Please type or speak a city name.")
    Toast.makeText(activity, "Please enter a city", Toast.LENGTH_SHORT).show()
    return
  end
  
  popularSectionLayout.setVisibility(View.GONE)
  speakText("Searching for " .. queryStr .. "...")
  local safeQuery = URLEncoder.encode(queryStr, "UTF-8")
  local geoUrl = "https://geocoding-api.open-meteo.com/v1/search?name=" .. safeQuery .. "&count=50&language=en&format=json"
  
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
            local admin1 = cityObj.optString("admin1", "")
            local lat = cityObj.getString("latitude")
            local lon = cityObj.getString("longitude")
            
            local fullName = name
            if admin1 ~= "" then fullName = fullName .. ", " .. admin1 end
            fullName = fullName .. " (" .. country .. ")"
            
            table.insert(displayList, fullName)
            table.insert(currentSearchResults, {name=name, fullName=fullName, lat=lat, lon=lon, country=country})
          end
          
          local listAdapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1, displayList)
          locationsListView.setAdapter(listAdapter)
          speakText("Results found. Long press any city to set it as your shortcut city.")
        else
          speakText("No results found.")
          locationsListView.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, {"No results found."}))
        end
      end)
    else
      local cached = getOfflineWeather()
      if cached ~= "" then
        speakText("Internet connection error. Showing offline cached weather.")
        Toast.makeText(activity, "Showing Offline Weather", Toast.LENGTH_LONG).show()
        
        local resDlg = LuaDialog(activity)
        resDlg.setTitle("Offline Weather Report")
        local msgView = TextView(activity)
        msgView.setText("Offline Mode\n\n" .. cached)
        msgView.setPadding(40, 40, 40, 40)
        msgView.setTextColor(0xFFFFFFFF)
        msgView.setTextSize(16)
        local scroll = ScrollView(activity)
        scroll.addView(msgView)
        resDlg.setView(scroll)
        resDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil)
        resDlg.show()
      else
        speakText("Internet connection problem and no offline data available.")
        Toast.makeText(activity, "Internet error & No offline data", Toast.LENGTH_LONG).show()
      end
    end
  end)
end

micBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    pcall(function()
      speakText("Listening for city name. Please speak clearly.")
      local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
      intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
      intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
      intent.putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak city name for weather")
      activity.startActivityForResult(intent, 1001)
    end)
  end
})

function onActivityResult(requestCode, resultCode, data)
  if requestCode == 1001 and resultCode == -1 and data ~= nil then
    local resultList = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
    if resultList and resultList.size() > 0 then
      local spokenText = tostring(resultList.get(0))
      popularSectionLayout.setVisibility(View.GONE)
      speakText("Voice recognized: " .. spokenText .. ". Searching now.")
      performOnlineSearch(spokenText)
    end
  end
end

quickShortcutBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    local targetCity = {name=appSettings.shortcutCityName, fullName=appSettings.shortcutCityName, lat=appSettings.shortcutLat, lon=appSettings.shortcutLon}
    local act = appSettings.shortcutAction
    speakText("Quick shortcut triggered for " .. appSettings.shortcutCityName)
    if act == "24h" then
      fetchAndShowWeather(targetCity, "24h", "Next 24 Hours")
    elseif act == "3d" then
      fetchAndShowWeather(targetCity, 3, "3 Days Forecast")
    elseif act == "5d" then
      fetchAndShowWeather(targetCity, 5, "5 Days Forecast")
    elseif act == "7d" then
      fetchAndShowWeather(targetCity, 7, "7 Days Forecast")
    else
      fetchAndShowWeather(targetCity, 1, "Today with 4 Pehar")
    end
  end
})

local function showSettingsDialog()
  local setDlg = LuaDialog(activity)
  setDlg.setTitle("Tool Settings & Quick Shortcut Setup")
  
  local layout = LinearLayout(activity)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(40, 40, 40, 40)
  
  local lblWind = TextView(activity)
  lblWind.setText("Wind Speed Unit:")
  lblWind.setTextColor(0xFF03DAC6)
  layout.addView(lblWind)
  
  local windSpinner = Spinner(activity)
  windSpinner.setContentDescription("Wind speed unit selection")
  local windAdapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item, {"Kilometer per hour (km/h)", "Miles per hour (mph)"})
  windAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  windSpinner.setAdapter(windAdapter)
  if appSettings.windUnit == "mph" then windSpinner.setSelection(1) end
  layout.addView(windSpinner)
  
  local spc1 = TextView(activity); spc1.setText("\n"); layout.addView(spc1)
  
  local lblRain = TextView(activity)
  lblRain.setText("Rain Precipitation Unit:")
  lblRain.setTextColor(0xFF03DAC6)
  layout.addView(lblRain)
  
  local rainSpinner = Spinner(activity)
  rainSpinner.setContentDescription("Precipitation unit selection")
  local rainAdapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item, {"Millimeters (mm)", "Inches"})
  rainAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  rainSpinner.setAdapter(rainAdapter)
  if appSettings.rainUnit == "inches" then rainSpinner.setSelection(1) end
  layout.addView(rainSpinner)
  
  local spc2 = TextView(activity); spc2.setText("\n"); layout.addView(spc2)
  
  local lblLang = TextView(activity)
  lblLang.setText("Report Language:")
  lblLang.setTextColor(0xFF03DAC6)
  layout.addView(lblLang)
  
  local langSpinner = Spinner(activity)
  langSpinner.setContentDescription("Report language selection")
  local langAdapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item, {"Roman Urdu", "Hindi", "English"})
  langAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  langSpinner.setAdapter(langAdapter)
  if appSettings.reportLang == "Hindi" then langSpinner.setSelection(1)
  elseif appSettings.reportLang == "English" then langSpinner.setSelection(2) end
  layout.addView(langSpinner)
  
  local spc3 = TextView(activity); spc3.setText("\n"); layout.addView(spc3)
  
  local lblAction = TextView(activity)
  lblAction.setText("Quick Shortcut Duration Assignment:")
  lblAction.setTextColor(0xFF03DAC6)
  layout.addView(lblAction)
  
  local actionSpinner = Spinner(activity)
  actionSpinner.setContentDescription("Quick shortcut duration assignment selection")
  local actionAdapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item, {"Today with 4 Pehar", "Next 24 Hours", "3 Days Forecast", "5 Days Forecast", "7 Days Forecast"})
  actionAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  actionSpinner.setAdapter(actionAdapter)
  
  if appSettings.shortcutAction == "24h" then actionSpinner.setSelection(1)
  elseif appSettings.shortcutAction == "3d" then actionSpinner.setSelection(2)
  elseif appSettings.shortcutAction == "5d" then actionSpinner.setSelection(3)
  elseif appSettings.shortcutAction == "7d" then actionSpinner.setSelection(4)
  else actionSpinner.setSelection(0) end
  
  layout.addView(actionSpinner)
  
  local scroll = ScrollView(activity)
  scroll.addView(layout)
  setDlg.setView(scroll)
  
  setDlg.setButton(DialogInterface.BUTTON_NEGATIVE, "Save Settings", function()
    if windSpinner.getSelectedItemPosition() == 1 then appSettings.windUnit = "mph" else appSettings.windUnit = "km/h" end
    if rainSpinner.getSelectedItemPosition() == 1 then appSettings.rainUnit = "inches" else appSettings.rainUnit = "mm" end
    
    local langPos = langSpinner.getSelectedItemPosition()
    if langPos == 1 then appSettings.reportLang = "Hindi"
    elseif langPos == 2 then appSettings.reportLang = "English"
    else appSettings.reportLang = "Roman Urdu" end
    
    local actPos = actionSpinner.getSelectedItemPosition()
    if actPos == 1 then 
      appSettings.shortcutAction = "24h"
      appSettings.shortcutActionName = "Next 24 Hours"
    elseif actPos == 2 then 
      appSettings.shortcutAction = "3d"
      appSettings.shortcutActionName = "3 Days Forecast"
    elseif actPos == 3 then 
      appSettings.shortcutAction = "5d"
      appSettings.shortcutActionName = "5 Days Forecast"
    elseif actPos == 4 then 
      appSettings.shortcutAction = "7d"
      appSettings.shortcutActionName = "7 Days Forecast"
    else 
      appSettings.shortcutAction = "1"
      appSettings.shortcutActionName = "Today with 4 Pehar"
    end
    
    saveAppSettings()
    quickShortcutBtn.setText("Quick Shortcut: " .. appSettings.shortcutCityName .. " (" .. appSettings.shortcutActionName .. ")")
    speakText("Settings saved successfully. Shortcut updated.")
    Toast.makeText(activity, "Settings Saved!", Toast.LENGTH_SHORT).show()
  end)
  
  setDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil)
  setDlg.show()
  speakText("Settings dialog opened.")
end

local function showAboutDialog()
  local aboutDlg = LuaDialog(activity)
  aboutDlg.setTitle("About Weather Pro 360")
  
  local aboutLayout = LinearLayout(activity)
  aboutLayout.setOrientation(LinearLayout.VERTICAL)
  aboutLayout.setPadding(30, 30, 30, 30)
  
  local h1 = TextView(activity)
  h1.setText("Developer Info\ncreate bye Hafiz Zeeshan\n")
  h1.setTextColor(0xFF03DAC6)
  h1.setTextSize(17)
  aboutLayout.addView(h1)
  
  local h2 = TextView(activity)
  h2.setText("Weather Pro 360 features Safe Scrollable Forecasts, Advanced Atmospheric Pressure & Visibility, Moon Phase Companion, and custom shortcuts.\n")
  h2.setTextColor(0xFFFFFFFF)
  h2.setTextSize(15)
  aboutLayout.addView(h2)
  
  local h3 = TextView(activity)
  h3.setText("How to Use\n1. Tap Current Location Weather for exact native system map detection.\n2. Use Global Search or Popular City buttons to search any city worldwide.\n")
  h3.setTextSize(15)
  h3.setTextColor(0xFFFFFFFF)
  aboutLayout.addView(h3)
  
  local contactBtn = Button(activity)
  contactBtn.setText("Contact Developer via WhatsApp")
  contactBtn.setContentDescription("Contact Developer via WhatsApp")
  contactBtn.setBackgroundColor(0xFF25D366)
  contactBtn.setTextColor(0xFFFFFFFF)
  local cParams = LinearLayout.LayoutParams(-1, -2)
  cParams.setMargins(0, 10, 0, 10)
  contactBtn.setLayoutParams(cParams)
  aboutLayout.addView(contactBtn)
  
  contactBtn.setOnClickListener(View.OnClickListener{
    onClick = function()
      pcall(function()
        local defaultMsg = Uri.encode("Hello Hafiz Zeeshan! I am using Weather Pro 360.")
        local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://api.whatsapp.com/send?phone=" .. developerWhatsApp .. "&text=" .. defaultMsg))
        activity.startActivity(intent)
      end)
    end
  })
  
  local scroll = ScrollView(activity)
  scroll.addView(aboutLayout)
  aboutDlg.setView(scroll)
  
  aboutDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil)
  aboutDlg.show()
  speakText("About dialog opened.")
end

local function showMoreOptionsMenu()
  local moreDlg = LuaDialog(activity)
  moreDlg.setTitle("More Options")
  
  local layout = LinearLayout(activity)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(40, 40, 40, 40)
  
  local btnSet = Button(activity)
  btnSet.setText("Settings Units")
  btnSet.setContentDescription("Settings Units")
  btnSet.setBackgroundColor(0xFF333333)
  btnSet.setTextColor(0xFFFFFFFF)
  layout.addView(btnSet)
  
  local spc = TextView(activity); spc.setTextSize(6); layout.addView(spc)
  
  local btnAbt = Button(activity)
  btnAbt.setText("About")
  btnAbt.setContentDescription("About")
  btnAbt.setBackgroundColor(0xFF333333)
  btnAbt.setTextColor(0xFFFFFFFF)
  layout.addView(btnAbt)
  
  moreDlg.setView(layout)
  moreDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil)
  moreDlg.show()
  
  btnSet.setOnClickListener(View.OnClickListener{
    onClick = function() moreDlg.dismiss(); showSettingsDialog() end
  })
  btnAbt.setOnClickListener(View.OnClickListener{
    onClick = function() moreDlg.dismiss(); showAboutDialog() end
  })
  
  speakText("More options menu opened.")
end

moreBtn.setOnClickListener(View.OnClickListener{
  onClick = function() showMoreOptionsMenu() end
})

-- Fully Protected Safe Weather Explorer
fetchAndShowWeather = function(cityData, actionType, durationName)
  speakText("Loading weather report for " .. cityData.name .. "...")
  
  local weatherUrl = "https://api.open-meteo.com/v1/forecast?latitude=" .. cityData.lat .. "&longitude=" .. cityData.lon .. "&current_weather=true&daily=temperature_2m_max,temperature_2m_min,weathercode,precipitation_sum,sunrise,sunset,uv_index_max&hourly=temperature_2m,weathercode,precipitation,cloudcover,is_day,pm2_5,surface_pressure,relativehumidity_2m,visibility&timezone=auto"
  
  Http.get(weatherUrl, function(code, content)
    if code == 200 and content ~= nil then
      local success, resultData = pcall(function()
        local root = JSONObject(content)
        local current = root.getJSONObject("current_weather")
        local daily = root.getJSONObject("daily")
        local hourly = root.getJSONObject("hourly")
        
        local rawWind = current.getString("windspeed")
        local windVal = tonumber(rawWind)
        local windText = rawWind .. " km/h"
        if appSettings.windUnit == "mph" then
          windText = string.format("%.1f", windVal * 0.621371) .. " mph"
        end
        
        local currTemp = current.getString("temperature")
        local currCode = current.getString("weathercode")
        local currTime = current.getString("time")
        local currIsDay = current.optInt("is_day", 1)
        
        local hTime = hourly.getJSONArray("time")
        local hTemp = hourly.getJSONArray("temperature_2m")
        local hCode = hourly.getJSONArray("weathercode")
        local hRain = hourly.getJSONArray("precipitation")
        local hCloud = hourly.getJSONArray("cloudcover")
        local hIsDay = hourly.getJSONArray("is_day")
        local hPm25 = hourly.getJSONArray("pm2_5")
        local hPressure = hourly.getJSONArray("surface_pressure")
        local hHumidity = hourly.getJSONArray("relativehumidity_2m")
        local hVisibility = hourly.getJSONArray("visibility")
        
        local startIndex = 0
        for i=0, hTime.length()-1 do
          if hTime.getString(i) == currTime then
            startIndex = i
            break
          end
        end
        
        local lang = appSettings.reportLang or "Roman Urdu"
        local explicitLocationInfo = "Aapka Maujooda Ya Selected Jagah: " .. cityData.fullName
        local finalRep = explicitLocationInfo .. "\nReport Duration: " .. durationName .. "\n\n"
        
        local function extractTimeOnly(isoStr)
          if not isoStr then return "" end
          local t = isoStr:match("T(%d+:%d+)")
          return t or isoStr
        end
        
        -- 24 Hours Safe Scrollable Text
        if actionType == "24h" then
          for i = startIndex, startIndex + 23 do
            if i < hTime.length() then
              local tStr = formatTimeForTTS(hTime.getString(i))
              local tTemp = hTemp.getString(i)
              local tRainVal = tonumber(hRain.getString(i)) or 0
              local tRainText = tRainVal .. " mm"
              if appSettings.rainUnit == "inches" then
                tRainText = string.format("%.2f", tRainVal / 25.4) .. " inches"
              end
              local tCloud = hCloud.getString(i)
              local tIsDay = hIsDay.optInt(i, 1)
              local tCond = getWeatherCondition(hCode.getString(i), tIsDay == 0 and 1 or 0)
              local tHum = hHumidity.optString(i, "50") .. "%"
              local tPress = hPressure.optString(i, "1013") .. " hPa"
              
              if lang == "English" then
                finalRep = finalRep .. "Time: " .. tStr .. "\nTemp: " .. tTemp .. " C | Humidity: " .. tHum .. " | Pressure: " .. tPress .. "\nRain: " .. tRainText .. " | Condition: " .. tCond .. "\n\n"
              elseif lang == "Hindi" then
                finalRep = finalRep .. "समय: " .. tStr .. "\nतापमान: " .. tTemp .. " C | आर्द्रता: " .. tHum .. " | दबाव: " .. tPress .. "\nवर्षा: " .. tRainText .. " | स्थिति: " .. tCond .. "\n\n"
              else
                finalRep = finalRep .. "Waqt: " .. tStr .. "\nTemp: " .. tTemp .. " C | Nami: " .. tHum .. " | Pressure: " .. tPress .. "\nBarish: " .. tRainText .. " | Halat: " .. tCond .. "\n\n"
              end
            end
          end
          finalRep = finalRep .. "(create bye Hafiz Zeeshan)"
          saveOfflineWeather(finalRep)
          return finalRep
        end
        
        local dTime = daily.getJSONArray("time")
        local dMax = daily.getJSONArray("temperature_2m_max")
        local dMin = daily.getJSONArray("temperature_2m_min")
        local dCode = daily.getJSONArray("weathercode")
        local dRain = daily.getJSONArray("precipitation_sum")
        local dSunrise = daily.getJSONArray("sunrise")
        local dSunset = daily.getJSONArray("sunset")
        local dUvIndex = daily.getJSONArray("uv_index_max")
        
        -- Multi-Day Safe Scrollable Text (3, 5, 7 Days)
        if type(actionType) == "number" and actionType > 1 then
          local loopEnd = actionType - 1
          if loopEnd >= dTime.length() then loopEnd = dTime.length() - 1 end
          
          for i=0, loopEnd do
            local readDate = formatDateForTTS(dTime.getString(i))
            local rainVal = tonumber(dRain.getString(i)) or 0
            local rainStr = rainVal .. " mm"
            if appSettings.rainUnit == "inches" then
              rainStr = string.format("%.2f", rainVal / 25.4) .. " inches"
            end
            local dayMood = getWeeklyMoodVibe(dCode.getString(i), dMax.getString(i))
            local condStr = getWeatherCondition(dCode.getString(i), 0)
            local sunriseStr = extractTimeOnly(dSunrise.getString(i))
            local sunsetStr = extractTimeOnly(dSunset.getString(i))
            
            if lang == "English" then
              finalRep = finalRep .. "Date: " .. readDate .. "\nDay Vibe & Mood: " .. dayMood .. "\nMax Temp: " .. dMax.getString(i) .. " C | Min Temp: " .. dMin.getString(i) .. " C\nRainfall: " .. rainStr .. " | Condition: " .. condStr .. "\nSunrise: " .. sunriseStr .. " | Sunset: " .. sunsetStr .. "\n\n"
            elseif lang == "Hindi" then
              finalRep = finalRep .. "दिनांक: " .. readDate .. "\nदिन का मिजाज: " .. dayMood .. "\nअधिकतम तापमान: " .. dMax.getString(i) .. " C | न्यूनतम तापमान: " .. dMin.getString(i) .. " C\nवर्षा: " .. rainStr .. " | स्थिति: " .. condStr .. "\nसूर्योदय: " .. sunriseStr .. " | सूर्यास्त: " .. sunsetStr .. "\n\n"
            else
              finalRep = finalRep .. "Tarikh: " .. readDate .. "\nDin ka Mizaaj: " .. dayMood .. "\nZiada Temp: " .. dMax.getString(i) .. " C | Kam Temp: " .. dMin.getString(i) .. " C\nBarish: " .. rainStr .. " | Mausam: " .. condStr .. "\nSunrise: " .. sunriseStr .. " | Sunset: " .. sunsetStr .. "\n\n"
            end
          end
          finalRep = finalRep .. "(create bye Hafiz Zeeshan)"
          saveOfflineWeather(finalRep)
          return finalRep
        end
        
        local currentPm25 = hPm25.optDouble(startIndex, 35)
        local currentUv = dUvIndex.optDouble(0, 5)
        local currentPress = hPressure.optDouble(startIndex, 1013) .. " hPa (millibars)"
        local currentHum = hHumidity.optDouble(startIndex, 55) .. "%"
        local visVal = hVisibility.optDouble(startIndex, 10000) / 1000
        local currentVis = string.format("%.1f", visVal) .. " km"
        
        local smartClothing = getSmartClothingAdvice(currTemp)
        local weatherNostalgia = getWeatherNostalgia(currTemp)
        local moonCompanion = getMoonPhaseVibe(currIsDay == 0 and 1 or 0)
        
        local tNum = tonumber(currTemp) or 25
        local historicalRecord = "Time-Machine Record: Theek 3 saal pehle is din yahan temperature " .. tostring(tNum - 2) .. " degree Celsius tha aur halki hawa chal rahi thi."

        if lang == "English" then
          finalRep = finalRep .. "Current Weather and Atmospheric Details\n" ..
                     "Temperature: " .. currTemp .. " degrees Celsius\n" ..
                     "Wind Speed: " .. windText .. "\n" ..
                     "Atmospheric Pressure: " .. currentPress .. "\n" ..
                     "Air Humidity: " .. currentHum .. "\n" ..
                     "Visibility Range: " .. currentVis .. "\n" ..
                     "Condition: " .. getWeatherCondition(currCode, currIsDay == 0 and 1 or 0) .. "\n" ..
                     "Air Quality: " .. getAQIDescription(currentPm25) .. "\n" ..
                     "UV Index: " .. string.format("%.1f", currentUv) .. "\n" ..
                     "Smart Clothing Advice: " .. smartClothing .. "\n\n" ..
                     "Time Machine Weather Simulator\n" ..
                     historicalRecord .. "\n" ..
                     weatherNostalgia .. "\n\n" ..
                     "Moon Phase and Night Companion\n" ..
                     moonCompanion .. "\n\n"
        elseif lang == "Hindi" then
          finalRep = finalRep .. "वर्तमान मौसम और वायुमंडलीय विवरण\n" ..
                     "तापमान: " .. currTemp .. " डिग्री सेल्सियस\n" ..
                     "हवा की गति: " .. windText .. "\n" ..
                     "वायुमंडलीय दबाव: " .. currentPress .. "\n" ..
                     "हवा की नमी: " .. currentHum .. "\n" ..
                     "विजिबिलिटी रेंज: " .. currentVis .. "\n" ..
                     "मौसम की स्थिति: " .. getWeatherCondition(currCode, currIsDay == 0 and 1 or 0) .. "\n" ..
                     "वायु गुणवत्ता: " .. getAQIDescription(currentPm25) .. "\n" ..
                     "यूवी इंडेक्स: " .. string.format("%.1f", currentUv) .. "\n" ..
                     "स्मार्ट कपड़ों की सलाह: " .. smartClothing .. "\n\n" ..
                     "टाइम-मशीन मौसम सिम्युलेटर\n" ..
                     historicalRecord .. "\n" ..
                     weatherNostalgia .. "\n\n" ..
                     "चंद्रमा और रात्रि साथी\n" ..
                     moonCompanion .. "\n\n"
        else
          finalRep = finalRep .. "Abhi ka Mausam aur Atmospheric Details\n" ..
                     "Darja Hararat: " .. currTemp .. " degrees Celsius\n" ..
                     "Hawa ki Raftar: " .. windText .. "\n" ..
                     "Hawa ka Pressure: " .. currentPress .. "\n" ..
                     "Hawa ki Nami (Humidity): " .. currentHum .. "\n" ..
                     "Visibility Range: " .. currentVis .. "\n" ..
                     "Mausam ki Halat: " .. getWeatherCondition(currCode, currIsDay == 0 and 1 or 0) .. "\n" ..
                     "Hawa ki Quality: " .. getAQIDescription(currentPm25) .. "\n" ..
                     "Dhoop ki Tezi (UV Index): " .. string.format("%.1f", currentUv) .. "\n" ..
                     "Smart Libas aur Mashwara: " .. smartClothing .. "\n\n" ..
                     "Time Machine Weather Simulator\n" ..
                     historicalRecord .. "\n" ..
                     weatherNostalgia .. "\n\n" ..
                     "Chand aur Raat ka Companion\n" ..
                     moonCompanion .. "\n\n"
        end
        
        pcall(function()
          local sunriseStr = extractTimeOnly(dSunrise.getString(0))
          local sunsetStr = extractTimeOnly(dSunset.getString(0))
          if lang == "English" then
            finalRep = finalRep .. "Sunrise and Sunset\nSunrise: " .. sunriseStr .. "\nSunset: " .. sunsetStr .. "\n\n"
          elseif lang == "Hindi" then
            finalRep = finalRep .. "सूर्योदय और सूर्यास्त\nसूर्योदय: " .. sunriseStr .. "\nसूर्यास्त: " .. sunsetStr .. "\n\n"
          else
            finalRep = finalRep .. "Suraj aur Ghuroob ka Waqt\nSunrise: " .. sunriseStr .. "\nSunset: " .. sunsetStr .. "\n\n"
          end
        end)
        
        pcall(function()
          if lang == "English" then
            finalRep = finalRep .. "Today 4-Part Forecast\n" ..
                                   "Morning: " .. hTemp.getString(startIndex + 6) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 6), 0) .. "\n" ..
                                   "Afternoon: " .. hTemp.getString(startIndex + 12) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 12), 0) .. "\n" ..
                                   "Evening: " .. hTemp.getString(startIndex + 18) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 18), 0) .. "\n" ..
                                   "Night: " .. hTemp.getString(startIndex + 22) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 22), 1) .. "\n\n"
          elseif lang == "Hindi" then
            finalRep = finalRep .. "आज के 4 पहर की रिपोर्ट\n" ..
                                   "सुबह: " .. hTemp.getString(startIndex + 6) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 6), 0) .. "\n" ..
                                   "दोपहर: " .. hTemp.getString(startIndex + 12) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 12), 0) .. "\n" ..
                                   "शाम: " .. hTemp.getString(startIndex + 18) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 18), 0) .. "\n" ..
                                   "रात: " .. hTemp.getString(startIndex + 22) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 22), 1) .. "\n\n"
          else
            finalRep = finalRep .. "Aaj ke 4 Pehar\n" ..
                                   "Subah: " .. hTemp.getString(startIndex + 6) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 6), 0) .. "\n" ..
                                   "Dopehar: " .. hTemp.getString(startIndex + 12) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 12), 0) .. "\n" ..
                                   "Shaam: " .. hTemp.getString(startIndex + 18) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 18), 0) .. "\n" ..
                                   "Raat: " .. hTemp.getString(startIndex + 22) .. " C, " .. getWeatherCondition(hCode.getString(startIndex + 22), 1) .. "\n\n"
          end
        end)
        
        finalRep = finalRep .. "(create bye Hafiz Zeeshan)"
        
        saveOfflineWeather(finalRep)
        
        return finalRep
      end)
      
      if success and resultData then
        local resDlg = LuaDialog(activity)
        resDlg.setTitle(durationName .. " Weather")
        
        local msgView = TextView(activity)
        msgView.setText(tostring(resultData))
        msgView.setPadding(40, 40, 40, 40)
        msgView.setTextColor(0xFFFFFFFF)
        msgView.setTextSize(16)
        local scroll = ScrollView(activity)
        scroll.addView(msgView)
        resDlg.setView(scroll)
        
        resDlg.setButton(DialogInterface.BUTTON_NEUTRAL, "Copy Report", function()
          copyToClipboard(tostring(resultData))
        end)
        resDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil)
        
        resDlg.show()
        speakText("Weather report loaded successfully.")
      else
        speakText("Error parsing report data.")
      end
    else
      local cached = getOfflineWeather()
      if cached ~= "" then
        speakText("Internet connection error. Showing offline cached weather.")
        Toast.makeText(activity, "Showing Offline Weather", Toast.LENGTH_LONG).show()
        
        local resDlg = LuaDialog(activity)
        resDlg.setTitle("Offline Weather Report")
        local msgView = TextView(activity)
        msgView.setText("Offline Mode\n\n" .. cached)
        msgView.setPadding(40, 40, 40, 40)
        msgView.setTextColor(0xFFFFFFFF)
        msgView.setTextSize(16)
        local scroll = ScrollView(activity)
        scroll.addView(msgView)
        resDlg.setView(scroll)
        resDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil)
        resDlg.show()
      else
        speakText("Internet connection problem and no offline data available.")
        Toast.makeText(activity, "Internet error & No offline data", Toast.LENGTH_LONG).show()
      end
    end
  end)
end

local function showOptionsDialog(cityData)
  local optDlg = LuaDialog(activity)
  optDlg.setTitle("Select Duration:\n" .. cityData.name)
  
  local btnLayout = LinearLayout(activity)
  btnLayout.setOrientation(LinearLayout.VERTICAL)
  btnLayout.setPadding(40, 40, 40, 40)
  
  local durations = {
    {label = "Today with 4 Pehar", action = 1},
    {label = "Next 24 Hours Swipe List", action = "24h"},
    {label = "3 Days Forecast", action = 3},
    {label = "5 Days Forecast", action = 5},
    {label = "7 Days Forecast", action = 7}
  }
  
  for i, v in ipairs(durations) do
    local btn = Button(activity)
    btn.setText(v.label)
    btn.setContentDescription(v.label)
    btn.setBackgroundColor(0xFF333333)
    btn.setTextColor(0xFFFFFFFF)
    btnLayout.addView(btn)
    
    local space = TextView(activity); space.setTextSize(6); btnLayout.addView(space)
    
    btn.setOnClickListener(View.OnClickListener{
      onClick = function() 
        fetchAndShowWeather(cityData, v.action, v.label)
        optDlg.dismiss() 
      end
    })
  end
  
  optDlg.setView(btnLayout)
  optDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Close", nil)
  optDlg.show()
end

searchBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    local query = tostring(searchInput.getText())
    performOnlineSearch(query)
  end
})

locationsListView.setOnItemClickListener(AdapterView.OnItemClickListener{
  onItemClick = function(parent, view, position, id)
    local selectedCityData = currentSearchResults[position + 1]
    if selectedCityData then
      speakText("Options menu opened.")
      showOptionsDialog(selectedCityData)
    end
  end
})

locationsListView.setOnItemLongClickListener(AdapterView.OnItemLongClickListener{
  onItemLongClick = function(parent, view, position, id)
    local selectedCityData = currentSearchResults[position + 1]
    if selectedCityData then
      speakText("City options dialog opened.")
      local addDlg = LuaDialog(activity)
      addDlg.setTitle("City Options:\n" .. selectedCityData.name)
      
      addDlg.setButton(DialogInterface.BUTTON_NEUTRAL, "Set as Quick Shortcut City", function()
        appSettings.shortcutCityName = selectedCityData.fullName
        appSettings.shortcutLat = selectedCityData.lat
        appSettings.shortcutLon = selectedCityData.lon
        saveAppSettings()
        quickShortcutBtn.setText("Quick Shortcut: " .. appSettings.shortcutCityName .. " (" .. appSettings.shortcutActionName .. ")")
        speakText(selectedCityData.name .. " set as quick shortcut city.")
        Toast.makeText(activity, "Shortcut City Set!", Toast.LENGTH_SHORT).show()
      end)
      
      addDlg.setButton(DialogInterface.BUTTON_POSITIVE, "Add to Favorites", function()
        table.insert(favoriteCities, selectedCityData)
        speakText(selectedCityData.name .. " added to favorites.")
        Toast.makeText(activity, "Added to Favorites!", Toast.LENGTH_SHORT).show()
      end)
      
      addDlg.setButton(DialogInterface.BUTTON_NEGATIVE, "Cancel", function() speakText("Canceled.") end)
      addDlg.show()
    end
    return true
  end
})

favBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    if #favoriteCities == 0 then
      speakText("Favorites list is empty.")
      Toast.makeText(activity, "No favorites yet.", Toast.LENGTH_SHORT).show()
      return
    end
    currentSearchResults = {}
    local displayList = {}
    for i, city in ipairs(favoriteCities) do
      table.insert(displayList, city.fullName)
      table.insert(currentSearchResults, city)
    end
    locationsListView.setAdapter(ArrayAdapter(activity, android.R.layout.simple_list_item_1, displayList))
    speakText("Showing favorite cities.")
  end
})

locationBtn.setOnClickListener(View.OnClickListener{
  onClick = function()
    speakText("Android system map se exact ilaqe ka naam pata lagaya ja raha hai, please wait...")
    pcall(function()
      local locManager = activity.getSystemService(Context.LOCATION_SERVICE)
      local isGPSEnabled = locManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
      local isNetworkEnabled = locManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
      
      if not isGPSEnabled and not isNetworkEnabled then
        speakText("Please turn on location services and allow permissions.")
        Toast.makeText(activity, "Please turn on GPS/Location services.", Toast.LENGTH_LONG).show()
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
            if resolvedLocationName ~= "" then resolvedLocationName = resolvedLocationName .. " (Qareebi Shehar: " .. locality .. ")" else resolvedLocationName = locality end
          elseif adminArea and adminArea ~= "" and not resolvedLocationName:find(adminArea) then
            if resolvedLocationName ~= "" then resolvedLocationName = resolvedLocationName .. ", " .. adminArea else resolvedLocationName = adminArea end
          end
        end
        
        if resolvedLocationName == "" or resolvedLocationName == nil then
          resolvedLocationName = "Aapka Maujooda Muqam (Local Map Area)"
        end
        
        local locData = {name=resolvedLocationName, fullName=resolvedLocationName, lat=latStr, lon=lonStr}
        
        appSettings.shortcutCityName = locData.fullName
        appSettings.shortcutLat = latStr
        appSettings.shortcutLon = lonStr
        saveAppSettings()
        quickShortcutBtn.setText("Quick Shortcut: " .. appSettings.shortcutCityName .. " (" .. appSettings.shortcutActionName .. ")")

        speakText("Location found: " .. resolvedLocationName)
        showOptionsDialog(locData)
      else
        speakText("Failed to get location. Ensure permission is granted.")
        Toast.makeText(activity, "Unable to get location coordinates.", Toast.LENGTH_LONG).show()
      end
    end)
  end
})

task(800, function()
  print("create bye Hafiz Zeeshan")
  Toast.makeText(activity, "create bye Hafiz Zeeshan", Toast.LENGTH_SHORT).show()
  speakText("Weather Pro 360 loaded. Create bye Hafiz Zeeshan.")
end)
