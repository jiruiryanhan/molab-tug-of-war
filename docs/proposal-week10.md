# final project proposal: tilt tug-of-war

## idea

i want to make a realtime multiplayer tug-of-war game for two iphones. each player tilts their phone to pull a shared rope toward their side. the first player to pull the middle marker past their goal wins. i want it to feel like a small physical game people can play together, without shaking the phone hard.

## basic version

- two players join the same game and choose opposite sides.
- both players hold their phones comfortably and set a neutral position before starting.
- tilting away from neutral adds pulling strength, with a limit so extreme angles do not give an advantage.
- both screens show the same rope position, a start state and a winner.
- a restart button begins another round.

first i'll test the tilt on one phone, then connect two phones. i plan to start from the class molobby/firebase example for the shared session and use the phone's motion data for input. the exact syncing method still needs testing. no matchmaking, chat or more than two players for the first version.

## week by week plan

- week 11, nov 13: discuss the proposal with a classmate. make a simple local rope screen and test the tilt input on an iphone. check neutral position and sensitivity.
- week 12, nov 20: connect two phones to one game. share each player's input and check that both screens agree on the rope position. add start, win and restart states.
- nov 27, thanksgiving break: leave time for catching up and fixing delay or connection problems. no regular class is listed this week.
- week 13, dec 4: playtest with two people. tune the pulling strength, fix confusing controls, and check what happens if someone disconnects or restarts.
- week 14, dec 11: finish the small version, record a short demo, and prepare the final presentation and documentation.

## week 10 update

- progress: chose the two-player tilt tug-of-war idea, expanded the proposal, made this repository and added a weekly plan. in week 9 i worked with the molobby study-status example; the tug-of-war game itself is not built yet.
- problems: i still need to test phone tilt sensitivity, network delay and how to keep the rope position consistent on both phones.
- plans: start with local tilt and rope movement, then test the shared game on two phones.
- questions: should one phone calculate the rope position for both players? is the class firebase setup suitable for this kind of frequent input? how often should the phones send updates?

## peer feedback

pending. i will discuss the proposal with a classmate and add the actual feedback and any changes afterward.

## sources and assistance

- [week 10 requirements](https://github.com/molab-itp/content-2026-ima/blob/main/weeks/10_multi.md#homework-week10)
- [course schedule](https://github.com/molab-itp/content-2026-ima#time--location--dates)
- [class molobby example](https://github.com/molab-itp/98-MoGallery-Private/tree/main/MoLobby), planned starting point, not copied into this repository.
- ai assistance: Waldo helped organize my existing game idea into this proposal and weekly plan. no gameplay implementation or playtest results are claimed here.
