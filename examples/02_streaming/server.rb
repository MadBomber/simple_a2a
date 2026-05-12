#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/02_streaming/server.rb

require_relative "../common_config"

# ---------------------------------------------------------------------------
# Streaming executor — streams an article at ~300 words per minute.
# ---------------------------------------------------------------------------
class StreamingExecutor < A2A::Server::AgentExecutor
  SECONDS_PER_WORD = (60.0 / 600).freeze  # 600 WPM → 0.1 s/word

  ARTICLE = <<~ARTICLE.freeze
    The Heaviest Word in the Bible — The God Particle

    You did not expect to find physics here.

    You picked up an essay about the Bible and now you are reading about mass, gravity, and particle accelerators. The suspicion is reasonable. These things belong in different rooms. Science over there. Scripture over here. Never introduce them.

    That assumption is the first thing this essay will examine. Solomon wrote that "it is the glory of God to conceal things, but the glory of kings is to search things out" (Proverbs 25:2). The investigation is not a trespass. It is a vocation.

    ## It's Greek to Me

    The word "physics" comes from the Greek word for nature — or more precisely, the way things are. Aristotle titled his foundational work on natural philosophy simply Physics. The discipline does not invent reality. It describes it. The apple fell before Newton named the force that pulled it. Spacetime curved before Einstein described its geometry. The field that gives particles their mass existed before Peter Higgs predicted it in 1964. Physics is the practice of looking at what is already there and reporting back accurately. The study of reality — not one interpretation of it, not a useful model of it. Reality itself.

    Genesis 1 is doing the same thing from a different angle.

    ## In the Beginning

    "In the beginning God created the heavens and the earth." (Genesis 1:1, ESV)

    That is not a metaphor for an inner spiritual state. It is a claim about what actually happened to actual matter and actual space. The opening verses of Scripture make physical claims: there was a beginning — not an eternal universe cycling endlessly through time, but a moment when space and matter came into existence. The earth was without form and void (Genesis 1:2) — the Hebrew is tohu wabohu, formless and empty, maximum disorder, no structure and no content. Then God spoke, and the first thing He made was light (Genesis 1:3) — brightness before substance, energy before matter. The writer of Genesis had no knowledge of particle physics. But what they named first, physics has since confirmed is genuinely foundational: light is massless, travels as both wave and particle, and can exist where matter cannot. The correspondence is not a coincidence waiting to be explained. It is an invitation to pay attention.

    The sequence that follows — three days of separation, three days of filling (Genesis 1:3–31) — is the account of physical reality being ordered and inhabited. Science asks how this reality behaves. Genesis asks whose idea it was and why. They are not enemies. They are two disciplines examining the same subject — one asking how it works, the other asking who made it and why.

    The astronomer Robert Jastrow was not a believer. He spent his career measuring the universe. In God and the Astronomers he described what happened when cosmology finally confronted the beginning it had resisted for decades:

    "For the scientist who has lived by his faith in the power of reason, the story ends like a bad dream. He has scaled the mountains of ignorance; he is about to conquer the highest peak; as he pulls himself over the final rock, he is greeted by a band of theologians who have been sitting there for centuries."

    Einstein added a fudge factor to his own equations — the cosmological constant — because his mathematics implied an expanding universe and he did not want the implications of a beginning. When Edwin Hubble confirmed the expansion in 1929, the beginning became unavoidable. Theologians had been saying "in the beginning" for three thousand years. They were not surprised.

    Physics and Scripture share a subject. What follows is both.

    ## Three Kinds of Mass

    Before we talk about gravity, we need to talk about mass. And before we talk about mass in physics, a small detour is in order.

    Catholics call their central act of worship "Mass." The name has nothing to do with what you are about to read. The liturgical word comes from the Latin missa — the past participle of mittere, to send or dismiss. The closing words of the service are Ite, missa est — Go, the dismissal is made. The congregation was gathered, fed spiritually and sacramentally, and then sent out. The service is named for its ending movement. You were assembled so that you could be dispatched.

    The physics word "mass" comes from Latin massa and Greek maza, meaning a lump or heap — originally a lump of dough. A physical clump of stuff. No connection to the liturgical word whatsoever. Two identical English words pointing at entirely different realities. Keep that observation in mind. It will matter before this essay is finished.

    "Mass" in everyday speech sits between the liturgical and the scientific. A mass of protesters. Mass hysteria. Weapons of mass destruction. Here the word means a large quantity of something gathered in one place — bulk, accumulation, a lot. Same Latin root as the physics term, stretched across general usage until it means something vague and large.

    Then there is mass in physics, which is precise and specific and does not mean a heap of anything.

    There are two kinds of mass in physics, and they turn out to be the same thing.

    Inertial mass is resistance to acceleration. Force equals mass times acceleration. The more mass an object has, the harder it is to move, stop, or change direction. This is what you feel when you push a stalled car versus a shopping cart. The car resists you. The shopping cart does not. That resistance is inertial mass.

    Gravitational mass is the property that causes objects to attract each other across space. It is the property that makes gravity work between bodies.

    Einstein's equivalence principle established that these two are identical. Standing in a gravitational field is physically indistinguishable from being accelerated. Mass is mass, regardless of how you measure it.

    Here is the crucial distinction: mass is intrinsic and weight is relational. You have the same mass on the moon, on Jupiter, floating in deep space. Your weight changes with every location because weight is the force your mass experiences in the presence of another mass. Weigh yourself on the moon and the scale reads one-sixth what it reads on earth. Your mass did not change. The moon simply has less mass than the earth and exerts less gravitational force on you.

    Mass is what you fundamentally are. Weight is what you feel in a given environment.

    For most of physics history, mass was treated as a brute fact. Things have it. That is simply the way things are. Nobody asked where it came from. Then the question became unavoidable.

    ## The God Particle

    The Standard Model of particle physics describes all fundamental particles as excitations of quantum fields. This framework is extraordinarily accurate — the most precisely tested theory in the history of science. But it could not explain why some particles have mass and others do not. The photon, the particle of light, has zero mass. It travels at the speed of light because nothing with mass can reach that speed. The electron has mass. The W and Z bosons that carry the weak nuclear force have mass. The reason for this difference was a gap that embarrassed physicists for decades.

    Peter Higgs and several colleagues proposed an answer in 1964. There is a field permeating all of space — invisible, everywhere, present at every point in the universe. Particles that interact with this field acquire mass. The more strongly a particle interacts with it, the more mass it has. Particles that do not interact with it — photons — pass through unimpeded at light speed.

    The standard analogy is a crowded room at a party. A celebrity enters and immediately gets surrounded — they can barely move through the crowd. They have acquired effective mass from the interaction. An unknown walks through the same room unnoticed and reaches the far wall in seconds. The crowd is the Higgs field. The interaction is mass.

    Without the Higgs field, no particle has mass. Without mass, there are no atoms. Without atoms, there is no matter. Without matter, there are no stars, no planets, no you. Everything races around at the speed of light — a universe of pure weightless energy. Substantial nothing.

    The Higgs boson is the particle associated with the Higgs field, the way a photon is the particle of the electromagnetic field. Physicists searched for it for fifty years. It was detected at CERN's Large Hadron Collider in 2012. Peter Higgs and François Englert received the Nobel Prize in Physics the following year.

    The name the particle carries is not what Higgs would have chosen. Physicist Leon Lederman coined it for his 1993 book. The original title was The Goddamn Particle — a tribute to how maddeningly difficult the thing was to find. His publisher refused it. They shortened it to The God Particle, and the name spread despite the protests of nearly every physicist who heard it.

    It spread because it accidentally captured something true.

    An invisible field, present everywhere in the universe, giving substance to particles that would otherwise have none. Without it, nothing has weight. Nothing has thereness. The field is what makes matter into something rather than nothing.

    Secular physicists reached the bottom of the question "where does mass come from?" and what they described — an invisible field, present everywhere, the source of all substance — was something theologians had been naming for three thousand years. The popular name was an accident. The description was not.

    A Hebrew word has been saying exactly this for three thousand years. We will get to it shortly.

    ## Gravity

    First, gravity.

    Gravity is one of the four fundamental forces of nature: the strong nuclear force, the weak nuclear force, electromagnetism, and gravity. If you ranked them by strength, gravity would come last — and not by a small margin. Electromagnetism is approximately ten to the power of thirty-six times stronger than gravity. A small magnet on your refrigerator holds itself against the gravitational pull of the entire planet without effort.

    Yet gravity is the force that structures the universe at large scales. Galaxies, solar systems, planets, the orbits of moons — all of it is gravity's architecture. How does the weakest force become the dominant architect?

    Two properties set it apart. Gravity is always attractive — it never repels. And it has infinite range. It weakens with distance according to a precise mathematical law — double the distance and the force drops to one quarter — but it never reaches zero. The most distant galaxy in the observable universe is still gravitationally connected to you. The pull is immeasurably small. It is not zero. The weakest force wins because it reaches everywhere and never turns off.

    Isaac Newton described gravity as a force acting at a distance. His equation predicted the motion of planets with extraordinary precision. Newton did not know why masses attracted each other across empty space. He described the effect with perfect accuracy and admitted he could not explain the mechanism.

    Albert Einstein could. In his general theory of relativity, gravity is not a force at all. Mass curves spacetime itself — the four-dimensional fabric of space and time in which everything exists. Objects do not fall toward each other because they are pulled by a mysterious force. They follow the straightest possible path through a space that has been bent by the presence of mass. The apple does not fall because Earth is pulling it. Earth's mass has curved the geometry of space around it, and the apple is following that geometry.

    Gravity is not a thing that exists alongside matter. It is what happens to space when matter is present. Gravity is the shape of reality in the presence of mass.

    Now watch what happens to the word.

    "The gravity of the situation." "She carries herself with gravitas." "A grave matter." The word migrated from its precise physical meaning into everyday language, where it now means anything serious, weighty, or worthy of solemnity. A good speech has gravity. A funeral has gravity. A bad decision carries grave consequences.

    The phenomenon did not change. The apple still falls at 9.8 meters per second squared. The planets still follow their curved paths through spacetime. Einstein's equations still hold. But the word "gravity" now does general duty for anything that feels heavy or serious, and no one reaching for it in conversation means spacetime curvature.

    This is the pattern.

    A word once pointed at a precise reality. It got borrowed across domains — the serious kind, the solemn kind, the impressive kind. Each borrowing added a thin layer of metaphor. Eventually the word stopped pointing at anything in particular and started functioning as a signal of weightiness in general. The reality did not change. The word became useless.

    Hold that pattern in mind.

    Because it happened to another word too. A word you have used in church. A word you have sung in hymns. A word that appears in Scripture more than four hundred times and has become so familiar, so borrowed, so spread across so many domains, that it now means whatever the context demands and nothing in particular.

    That word is glory.
  ARTICLE

  WORDS = ARTICLE.split.freeze

  def call(ctx)
    ctx.task.start!
    ctx.emit_status

    WORDS.each_with_index do |word, i|
      sleep SECONDS_PER_WORD
      text     = i.zero? ? word : " #{word}"
      artifact = A2A::Models::Artifact.new(
        index:      0,
        parts:      [A2A::Models::Part.text(text)],
        append:     i > 0,
        last_chunk: i == WORDS.length - 1
      )
      ctx.emit_artifact(artifact, append: i > 0, last_chunk: i == WORDS.length - 1)
    end

    ctx.task.complete!
    ctx.emit_status(final: true)
  end
end

# ---------------------------------------------------------------------------
# Agent card
# ---------------------------------------------------------------------------
card = A2A::Models::AgentCard.new(
  name:        "StreamingAgent",
  version:     "1.0",
  description: "Streams article content word-by-word at ~600 WPM via SSE",
  capabilities: A2A::Models::AgentCapabilities.new(streaming: true),
  skills: [
    A2A::Models::AgentSkill.new(
      name:        "stream",
      description: "Returns article text word-by-word via SSE at 600 WPM"
    )
  ],
  interfaces: [
    A2A::Models::AgentInterface.new(
      type:    "json-rpc",
      url:     "http://localhost:9292",
      version: "1.0"
    )
  ]
)

puts <<~HEREDOC
  Starting StreamingAgent on http://localhost:9292
  Streaming #{StreamingExecutor::WORDS.length} words at 600 WPM (~#{(StreamingExecutor::WORDS.length / 600.0).ceil} min)
  Press Ctrl-C to stop.

HEREDOC

A2A.server(agent_card: card, executor: StreamingExecutor.new).run
