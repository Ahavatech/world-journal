<?php

namespace APP\plugins\generic\worjAwards;

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class WorjAwardsMigration extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('worj_award_nominations')) {
            Schema::create('worj_award_nominations', function (Blueprint $t) {
                $t->bigIncrements('nomination_id');
                $t->bigInteger('context_id');
                $t->string('category', 255);
                $t->string('nominee_name', 255);
                $t->string('nominee_email', 255)->nullable();
                $t->string('article_ref', 500)->nullable();
                $t->text('statement');
                $t->string('nominator_name', 255);
                $t->string('nominator_email', 255);
                $t->string('status', 20)->default('received');
                $t->string('award_period', 100)->nullable();
                $t->dateTime('created_at');
                $t->dateTime('decided_at')->nullable();
                $t->index(['context_id', 'status'], 'worj_award_nominations_status');
            });
        }
        if (!Schema::hasTable('worj_award_scores')) {
            Schema::create('worj_award_scores', function (Blueprint $t) {
                $t->bigIncrements('score_id');
                $t->bigInteger('nomination_id');
                $t->bigInteger('judge_user_id');
                $t->tinyInteger('originality')->nullable();
                $t->tinyInteger('quality')->nullable();
                $t->tinyInteger('impact')->nullable();
                $t->tinyInteger('contribution')->nullable();
                $t->tinyInteger('conflict')->default(0);
                $t->text('comment')->nullable();
                $t->dateTime('updated_at');
                $t->unique(['nomination_id', 'judge_user_id'], 'worj_award_scores_unique');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('worj_award_scores');
        Schema::dropIfExists('worj_award_nominations');
    }
}
